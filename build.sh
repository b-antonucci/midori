cd ui
gleam build
cd ..
cp ui/build/dev/javascript/ priv/static/ui/ -r
cp ui/gchessboard/assets priv/static/ -r
gleam run