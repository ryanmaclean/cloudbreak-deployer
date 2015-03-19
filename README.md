Cloudbreak Deployer helps to deploy a cloudbreak environment into docker containers.

## Installation


## Core Containers

- **uaa**: OAuth Identity Server
- cloudbreak
- persicope
- uluwatu
- sultans

## System Level Containers

- consul: Service Registry
- registrator: automatically registers/deregisters containers into consul

## Release Process of Clodbreak Deployer tool

the master branch is always built on [CircleCI](https://circleci.com/gh/sequenceiq/cloudbreak-deployer).
When you wan’t a new release, all you have to do:

- create a PullRequest for the release branch:
  - make sure you change the `VERSION` file
  - update `CHANGELOG.md` with the release date
  - create a new **Unreleased** section in top of `CHANGELOG.md`

Once the PR is merged, CircleCI will a new release on [githu](),
with the help of the [gh-release](https://github.com/progrium/gh-release) tool.

## Credits

This tool, and the PR driven release, is very much inspired by [glidergun](https://github.com/gliderlabs/glidergun). Actually it
could be a fork of it. The reason it’s not a fork, because we wanted to have our own binary with all modules
built in, so only a single binary is needed.
