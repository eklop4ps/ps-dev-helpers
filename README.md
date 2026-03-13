# PS Dev Helpers
Powershell scripts to improve quality of life for AL developers

## Quickstart

### Create profile
You need to run this only once.
1. Open Powershell
2. Run `$profile`. This will create a Powershell profile file.

### Add script to profile
1. Open Powershell and  run `code $profile`
3. Paste the content of the script you want to use into the profile and save it.
4. Restart Powershell

## Scripts

## FindALObjectIdRanges.ps1 (v0.1])
This scripts collects the IDs of the AL objects in the app, divides it into ranges and outputs a JSON-snippet that can be copied to the app.json key `idRanges`.

**Usage**: run `GetRanges` from a `/app` or `/test` directory. Then copy the JSON-snippet to the app.json