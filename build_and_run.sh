git clone git@github.com:macroby/gchess.git
git clone git@github.com:macroby/gleam_erlexec.git
cd ui
git clone git@github.com:macroby/gchessboard.git
gleam build
cd ..
mkdir priv
mkdir priv/static
mkdir priv/static/ui
cp ui/index.js priv/static/
cp ui/build/dev/javascript/ priv/static/ui/ -r
cp ui/gchessboard/assets priv/static/ -r
gleam run