<p align="center">
  <br>
  <br>
  <img src="https://preview.condensation.io/assets/img/condensation-long-icon.svg" alt="Condensation" width="460">
  <br>
</p>

<h1 align="center">
  Perl implementation of Condensation
</h1>

## About
Condensation enables to build modern applications while ensuring data ownership and security.
It's a one stop open source project to match the next decades complex security challenges and to protect digital rights.

## Command line tools
The Perl implementation comes with the CDS command line tools. These tools are accessible via

```sh
cds
```

To enable tab completion, add the following line to your .bashrc or .bash_aliases file:
```sh
complete -o nospace -C cds cds
```

The tools are useful to query a store, and display objects and records:

```sh
# List an account
cds list 1207dcf456abc1733afee601726fa0aba3e6a4a7eb9f00ffcc1f60dfc2c9e75a on http://examples.condensation.io

# Open an envelope
cds open envelope 1142336ab6e73ea2c27990793d38a56274cedcdd635476240d1d14177a95f844 on http://examples.condensation.io using ./key-pair

# Display an object
cds show object e5cbfc282e1f3e6fd0f3e5fffd41964c645f44d7fae8ef5cb350c2dfd2196c9f on http://examples.condensation.io

# Display a record object
cds show record e5cbfc282e1f3e6fd0f3e5fffd41964c645f44d7fae8ef5cb350c2dfd2196c9f on http://examples.condensation.io
```

The tools also allow you to upload and download objects from stores, or transfer object trees from one store to another:

```sh
# Wrap a file into an object, and upload it
# Note that the object will be garbage collected unless it is referenced from another object or account.
cds put object with LogoWhite.png encrypted with c8140fb744735fed3782f56a3b7c6615ef250983a388b53561707aa449da8bae onto http://examples.condensation.io

# Download and save an object
cds save data of 648903c93fb325fe80d8a6c8f7fad5a3e1b13f14b7bb9ab5b0618aaeb32975a9 on http://examples.condensation.io decrypted with c8140fb744735fed3782f56a3b7c6615ef250983a388b53561707aa449da8bae as LogoWhite.png

# Transfer a tree from one store to another
cds transfer 1142336ab6e73ea2c27990793d38a56274cedcdd635476240d1d14177a95f844 from http://examples.condensation.io to ./store
```

Furthermore the tools can generate an display key pairs:

```sh
# Create a key pair and store it as file "thomas"
cds create key pair ./thomas

# Show a key pair
cds show ./thomas
```

The tools can also create and manage folder stores:

```sh
# Create a local folder store
cds create store ./store

# Change the permission scheme of a folder store
cds set permission scheme of ./store to user thomas

# Run cleanup (garbage collection) of a folder store
cds collect garbage of ./store

# Add an account (only necessary if account auto-creation is disabled)
cds add account for 1207dcf456abc1733afee601726fa0aba3e6a4a7eb9f00ffcc1f60dfc2c9e75a on ./store

```

The tools come with a simple HTTP store:

```sh
cds start http server for ./store on port 8080
```

The tools create a key pair, which can store to save your own data:

```sh
# Show an overview and read messages
cds

# Set a messaging store
cds use http://examples.condensation.io for messaging

# Show add a member to my actor group (not that the other actor needs to join me as well)
cds join member 8dcfb671343156b5f70ac0aea13487c112b24adb65c8119f9776afc056e0fcc2 on https://examples.condensation.io

# Activate the member (to share group data with it)
cds set member 8dcfb671343156b5f70ac0aea13487c112b24adb65c8119f9776afc056e0fcc2 active

# Discover the actor group of somebody else
cds discover 4eca25fb527755cb275729b2d06242922d48159989d9add539302e41bcabd75b on https://examples.condensation.io
```

## Using the Perl module

The Perl module is imported with:

```perl
use CDS;
```

The examples folder contains a few Perl scripts using the Perl module.

## Installation

There are three ways to install this module and the command line tools:

1. Using [CPAN](https://linux.die.net/man/3/cpan), to install the Perl module and the command line tools.
2. By manually downloading the Perl module *CDS.pm* and the command line tools *cds*.
3. By downloading the single-file *cds* script.

### 1. Installing via CPAN

To install via CPAN, open a terminal and type:

```sh
cpan install CDS
```

or:

```sh
sudo cpan install CDS
```

### 2. Downloading the files manually

Download the following files:

- [CDS.pm](https://github.com/CondensationDS/Condensation-Perl/blob/master/editions/cli/CDS.pm)
- [cds](https://github.com/CondensationDS/Condensation-Perl/blob/master/editions/cli/cds)

and store the files in the same folder. To use the cds command from anywhere, add that folder to your PATH variable.

### 3. Downloading the single-file command line tools

Download the following file:

- [cds](https://github.com/CondensationDS/Condensation-Perl/blob/master/editions/single-file-cli/cds)

and store it in a folder which is in your PATH environment.

[Learn more about the project on our main repository](https://github.com/CondensationDS/Condensation)
