# Installation

Pode is a PowerShell module that can be installed from either Chocolatey, PowerShell Gallery, or Docker. Once installed, you can import the module into your PowerShell scripts.

## Chocolatey

[![Chocolatey](https://img.shields.io/chocolatey/dt/pode.svg?label=Downloads&colorB=a1301c)](https://chocolatey.org/packages/pode)

To install Pode via Chocolatey, the following command can be used:

```powershell
choco install pode
```

## PowerShell Gallery

[![PowerShell](https://img.shields.io/powershellgallery/dt/pode.svg?label=Downloads&colorB=085298)](https://www.powershellgallery.com/packages/Pode)

To install Pode from the PowerShell Gallery, you can use the following:

```powershell
Install-Module -Name Pode
```

## Docker

[![Docker](https://img.shields.io/docker/stars/badgerati/pode.svg?label=Stars)](https://hub.docker.com/r/badgerati/pode/)
[![Docker](https://img.shields.io/docker/pulls/badgerati/pode.svg?label=Pulls)](https://hub.docker.com/r/badgerati/pode/)

Pode can run on *nix environments, therefore it only makes sense for there to be Docker images for you to use! The images use PowerShell Core on either an Ubuntu Xenial image (default), or an ARM32 image (for Raspberry Pis).

* To pull down the default Pode image you can do:

```powershell
# for latest
docker pull badgerati/pode:latest

# or the following for a specific version:
docker pull badgerati/pode:0.29.0
```

* To pull down the ARM32 Pode image you can do:

```powershell
# for latest
docker pull badgerati/pode:latest-arm32

# or the following for a specific version:
docker pull badgerati/pode:0.29.0-arm32
```

Once pulled, you can [view here](../Docker) on how to use the image.

## Using the Module

After you have installed the module all functions should be readily available to you. In the case of the Docker images, the module is pre-installed for you.

If you have any issues then you can try and import the module into your server scripts:

```powershell
Import-Module Pode
```