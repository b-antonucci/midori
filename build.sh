git clone https://github.com/macroby/gchessboard.git
cd ui
gleam build
cd ..
cp ui/build/dev/javascript/gchessboard priv/static/ -r
gleam run