# Google Play listing assets

Package: `com.crownparkcomputing.retroatarist`

The `en-US` listing text is stored in `listing-en-US.json`. The icon and
feature graphic use the application’s existing full-bleed Retro family
branding. Phone screenshots are unedited 1920x1080 captures from the Android
application running on a physical device; the lead image shows the bundled
EmuTOS core demo in operation.

Apply the listing with the local Play Console automation:

```sh
/home/jon/playstore-automation/bin/playctl \
  --key /home/jon/playstore-automation/config/service-account.json \
  --app com.crownparkcomputing.retroatarist \
  list en-US --set --file store/play/listing-en-US.json
```

The service-account key is deliberately outside this repository. Do not add
credentials or personal RetroMedia login details to distributable builds or
store assets.
