git clone git@github.com:byusti/gchess.git
cd ui
git clone git@github.com:byusti/gchessboard.git
gleam build
cd ..
mkdir priv
mkdir priv/static
mkdir priv/static/ui
cp ui/index.js priv/static/
cp ui/build/dev/javascript/ priv/static/ui/ -r
cp ui/gchessboard/assets priv/static/ -r
# gleam export erlang-shipment
gleam run