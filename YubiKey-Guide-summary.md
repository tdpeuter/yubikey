# Getting started with YubiKeys

A summary of the [long guide](./YubiKey-Guide.md). It assumes basic knowledge of Linux and handling drives.

## Prerequisites

- [ ] One or more YubiKeys
- [ ] One or more USB drives
- [ ] A fair die with 6 faces
- [ ] A piece of paper that can be destroyed afterwards
- [ ] A piece of paper that will be kept in a safe place

## Getting a YubiKey

[Verify your YubiKey(s)](https://support.yubico.com/hc/en-us/articles/360013723419-How-to-Confirm-Your-Yubico-Device-is-Genuine) by visiting [yubico.com/genuine](https://www.yubico.com/genuine/). Select *Verify Device* to begin the process. Touch the YubiKey when prompted and allow the site to see the make and model of the device when prompted. This device attestation may help mitigate [supply chain attacks](https://media.defcon.org/DEF%20CON%2025/DEF%20CON%2025%20presentations/DEF%20CON%2025%20-%20r00killah-and-securelyfitz-Secure-Tokin-and-Doobiekeys.pdf).

## Preparing an environment

### Ephermal, air-gapped system

Build an air-gapped NixOS LiveCD image using this repository. (So, clone this repo first.)

```sh
nix flake update --commit-lock-file
nix build --experimental-features "nix-command flakes" \
   .#nixosConfigurations.yubikeyLive.x86_64-linux.config.system.build.isoImage
```

Next, put it on a USB drive. I use a dedicated drive running [Ventoy](https://github.com/ventoy/Ventoy).

### USB drive(s)

You will need a way to:

- [ ] Boot the LiveCD (see previous step).
- [ ] Store data on an encrypted storage device.
- [ ] Store data on a clear storage device.

You can choose to put every part on a separate USB drive, or combine these into a single storage device. However, it is recommended to create and partition the encrypted drive in the LiveCD. 

I will leave these steps to you, as there is no single right way to do this.

You will probably want to save the passphrase for the encrypted USB drive.

```sh
# Partition the drive 

# Format the clear partition
mkfs.fat /dev/sdy1

# Format the encrypted partition
dd bs=4K if=/dev/urandom of=/dev/sdx1 status=progress

cryptsetup --type luks2 \
   --cipher aes-xts-plain64 \
   --key-size 512 \
   --hash sha512 \
   --iter-time 5000 \
   --pbkdf argon2id \
   --use-urandom \
   --verify-passphrase \
   luksFormat /dev/sdx1
cryptsetup luksOpen /dev/sdx1 encrypted_usb

dd bs=128M if=/dev/zero of=/dev/mapper/encrypted_usb status=progress

mkfs.ext4 /dev/mapper/encrypted_usb
```

## Setting up GnuPG

**Note:** It is possible to generate PGP keys on the YubiKey itself, without ever exporting the key. This makes sure it cannot be leaked, but it also prevents us from creating a backup YubiKey with the same PGP key. That's why we will create the keys on a (safe) system and back those up in a secure way.

Boot from the created LiveCD. Preferrably, the host should not have additional storage devices connected to it. Networking is disabled in the LiveCD to prevent leakage.

This guide will use environment variables for various options.

Check if `${GNUPGHOME}` is set and that the configuration file `${GNUPGHOME}/gpg.conf` exists. Check the configuration if you want. If the file is not there, something has gone wrong during the creation of your LiveCD.

Set your identity and the expiration date of the keys you are about to create.

```sh
IDENTITY="Your Name <your@mail>"
EXPIRATION=1y
```

### Keys passphrase

Create a passphrase that will be used to issue the Certify key and Subkeys.

I will describe (a variant of) the [Diceware](https://secure.research.vt.edu/diceware) method:

Decide how may words your passphrase will be. It is recommended to take 6 words or more for good security.

For every word, roll your die 5 times. Write down the numbers. Retrieve the corresponding words from the [Diceware list in a language of your choice](https://theworld.com/~reinhold/diceware.html#Diceware%20in%20Other%20Languages|outline). Your passphrase is now the combination of these words, with hyphens in between.

If you like, you can add some numbers in between as well.

It is recommended to write this passphrase down on a piece of paper that you will keep in a safe place afterwards.

Set the environment variable.

```sh
PASS="YOUR-PASSPHRASE"
```

### Create a Certify key

The Certify key should not have an expiration date.

```sh
gpg --batch --passphrase "${PASS}" \
   --quick-generate-key "${IDENTITY}" \
   rsa4096 cert never

# Retrieve the Certify key identifier using command line, but manually is fine too.
KEYID=$(gpg -K | grep -Po "(0x\w+)")
# Set the Certify key fingerprint.
KEYFPR=$(gpg --fingerprint "${KEYID}" | grep -Eo '([0-9A-F][0-9A-F ]{49})' | head -n 1 | tr -d ' ')
```

### Create Subkeys

Create a Signature, Encryption and Authentication Subkey. Use the same passphrase.

```sh
gpg --batch --pinentry-mode=loopback --passphrase "${PASS}" \
   --quick-add-key "${KEYFPR}" \
   rsa4096 {sign,encrypt,auth} "${EXPIRATION}"
```

The output of

```sh
gpg -K
```

should now show your `[C]`ertify, `[S]`ignature, `[E]`ncryption and `[A]`uthentication keys, with the set expiration dates for each.

### Backup your keys

Make sure none of this gets saved (you are using an ephermal, air-gapped system).

```sh
gpg --output ${GNUPGHOME}/${KEYID}-Certify.key \
   --batch --pinentry-mode=loopback --passphrase "${PASS}" \
   --armor --export-secret-keys ${KEYID}

gpg --output ${GNUPGHOME}/${KEYID}-Subkeys.key \
   --batch --pinentry-mode=loopback --passphrase "${PASS}" \
   --armor --export-secret-subkeys ${KEYID}

gpg --output ${GNUPGHOME}/${KEYID}.asc \
   --armor --export ${KEYID}
```

Copy this over to your encrypted USB drive.

Alternatively, if you don't have a spare USB drive, see [Moving GPG Keys Privately - Josh Habdas](https://web.archive.org/web/20210803213236/https://habd.as/post/moving-gpg-keys-privately/).

```sh
mkdir -p /mnt/usb0
cryptsetup luksOpen /dev/sdx1 encrypted_usb
mount /dev/mapper/encrypted_usb /mnt/usb0
mkdir -p /mnt/usb0/.secrets
cp -av ${GNUPGHOME} /mnt/usb0/.secrets/gnupg
umount /mnt/usb0
cryptsetup close encrypted_usb
```

Also export the public key to your clear USB drive.

```sh
mkdir -p /mnt/usb1
mount /dev/sdx1 /mnt/usb1
mkdir -p /mnt/usb1/public/gnupg
gpg --armor --export ${KEYID} | tee /mnt/usb1/public/gnupg/${KEYID}-$(date +%F).asc
chmod 0444 /mnt/usb1/public/gnupg/0x*.asc
umount /mnt/usb1
```

## Setting up your YubiKey

Do this for every YubiKey you wish to use.

### Reset your key

If you have previously used your YubiKey to store PGP keys, you will have to reset those.

```sh
ykman openpgp reset
```

### Enable KDF

With KDF enabled, the YubiKey only stores a hash of the PIN, preventing the PIN from being passed as plain text.

```sh
gpg --command-fd=0 --card-edit
> admin
> kdf-setup
> 12345678 # Default admin password
> quit
```

### Change the PINs

Choose a new Admin (at least 8 chars) and User (at least 6 chars) pin (at most 127 chars). You will probably want to save these somewhere safe.

Set these as environment variables.

```sh
ADMIN_PIN="YOUR-ADMIN-PIN"
USER_PIN="YOUR-USER-PIN"
```

Update the YubiKey PINs.

```sh
# Change the Admin PIN
gpg --command-fd=0 --change-pin
> 3
> 12345678
> ${ADMIN_PIN}
> ${ADMIN_PIN}
> q

# Change the User PIN
gpg --command-fd=0 --change-pin
> 1
> 123456
> ${USER_PIN}
> ${USER_PIN}
> q
```

Remove and insert you YubiKey.

### Set attributes

```sh
gpg --command-fd=0 --edit-card
> admin
> name
> YourLastName
> YouFirstName
> ${ADMIN_PIN}
> lang
> sv
> sex
> m
> login
> your@mail
> quit
```

Check the output of

```sh
gpg --command-fd=0 --edit-card
```

### Transfer Subkeys

**Note:** If you are going to duplicate the keys to another YubiKey, omit the `save` instruction until you are configuring your last YubiKey. When the `save` instruction is given, the key is moved instead of copied.

```sh
# Signature key
gpg --command-fd=0 --edit-key ${KEYID}
> key 1
> keytocard
> 1
> ${PASS}
> ${ADMIN_PIN}
> save

# Encryption key
gpg --command-fd=0 --edit-key ${KEYID}
> key 2
> keytocard
> 2
> ${PASS}
> ${ADMIN_PIN}
> save

# Authentication key
gpg --command-fd=0 --edit-key ${KEYID}
> key 3
> keytocard
> 3
> ${PASS}
> ${ADMIN_PIN}
> save
```

Now, if you run `gpg -K`, you should see your keys with the `>` tag, indicating that the key is stored on the smart card.

If you are sure you have saved all your passphrases, you can `reboot` the system to clear your traces.

## Going back

Import the private keys from your encrypted USB stick again.

```
gpg --import "${GNUPGHOME}/${KEYID}-Certify.key"
```

Add the extra identity.

```
gpg --edit-key ${KEYID}

gpg> adduid

# Follow the steps
# ...

gpg> list

# Check the number of the id you want to make primary.

gpg> <number>

# A star should appear next to the primary id.

gpg> primary

gpg> save
```

Now export the public key again. You will have to send it to your contacts and public key server(s) afterwards.

## Questions and Answers

**What are shadowed keys?**

Sometimes, or maybe always, there is a "shadowed" copy of your key in `~/.gnupg/private-keys-v1.d/`. These are not your actual private keys. They only store some information about the smart card, such as its serial number, and the public key. This is used to request the actual private key when needed.

Sources:

- https://dev.gnupg.org/T2291
- https://www.gnupg.org/blog/20240125-smartcard-backup-key.html

## Notes and TODOs

- [ ] What should be the encryption method for our keys (currently rsa4096)?
- [ ] Are the headers of our encrypted USB visible?
- [ ] Set public key URL card attributes?

