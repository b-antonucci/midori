cd ui
gleam build
cd ..
mkdir priv/static/ui
cp ui/index.js priv/static/
cp ui/build/dev/javascript/ priv/static/ui/ -r
cp ui/gchessboard/assets priv/static/ -r
gleam run