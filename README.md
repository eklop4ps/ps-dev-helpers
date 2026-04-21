# PS Dev Helpers
Powershell scripts to improve quality of life for AL developers

## Quickstart

### Create profile
You need to run this only once.
1. Open Powershell
2. Run `$profile`. This will create a Powershell profile file.

### Add script to profile
1. Open Powershell and  run `code $profile`
1. Include scripts like this: `. .\<path to repo>\CloneRepo.ps1`.
1. Check the documentation below to see if you need to make additional changes.
1. Restart Powershell to reload the profile

## Scripts

### FindALObjectIdRanges.ps1 (v0.1)
This scripts collects the IDs of the AL objects in the app, divides it into ranges and outputs a JSON-snippet that can be copied to the app.json key `idRanges`.

**Usage**: run `GetRanges` from a `/app` or `/test` directory. Then copy the JSON-snippet to the app.json

### CloneRepo
This scripts automates the creation of a local dev environment, based on the ticket no you're going to work on.  It assumes you have the required authentication and VS Code set up.

#### Configuration

This scripts needs to know where to clone the repo's. Follow these steps to add the required parameter to your PS profile.

1. Run command 'code `$profile'
2. Add this line to the top of the file: `$global:DEV_ROOT = 'C:\dev\...';` Replace the path with the full path to the root directory of your AL projects
3. Restart Powershell/Terminal.

**Usage**: run `cr` from anywhere. 