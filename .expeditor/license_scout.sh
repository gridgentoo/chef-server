#!/bin/bash

set -eou pipefail

echo "--- Installing Automate UI dependencies"
pushd components/automate-ui
  npm install
popd

echo "--- Installing Chef UI Library dependencies"
pushd components/chef-ui-library
  npm install
popd

echo "--- Installing Elixir dependencies"
pushd components/notifications-service/server
  mix local.hex --force
  mix deps.get
popd

echo "+++ Running License Scout"
# a bug requires the use of `--format csv` but the
# format of the generated manifest is still json
license_scout --only-show-failures --format csv
