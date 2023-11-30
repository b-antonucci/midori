cd ui
gleam build
cd ..
mkdir priv/static/ui
cp ui/build/dev/javascript/ priv/static/ui/ -r
cp ui/gchessboard/assets priv/static/ -r
gleam run