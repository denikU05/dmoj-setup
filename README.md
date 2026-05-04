# DMOJ Docker Deployment

Scripts to deploy, manage, and uninstall a DMOJ (Modern Online Judge) instance and its judge server using Docker. Disables `mathoid`.

## Prerequisites
Linux environment (Ubuntu/Debian recommended) and `git` installed.

## Setup Guide

### 1. Configuration

Create configuration file from example:
```bash
cp config.env.example config.env
```

And fill in your values before starting the installation.


### 2. Installation
Make the scripts executable and run the install script:

```bash
chmod +x install.sh start.sh uninstall.sh
./install.sh
```
The script will install Docker and Python3 (if necessary), clone the repositories into a local `dmoj/` directory, build the Docker images, and start the containers.

After the script finishes, the site will be available at `http://<HOST>`.

## Management

### Start
To bring up the containers after a reboot or if they were stopped:
```bash
./start.sh
```

### Uninstall
To completely remove the DMOJ installation, including all containers, database volumes, and the `dmoj/` directory:
```bash
./uninstall.sh
```