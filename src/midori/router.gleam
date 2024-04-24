import gleam/io
import gleam/string_builder
import midori/web.{type Context}
import wisp.{type Request, type Response}

const html = "
<!DOCTYPE html>
<html lang=\"en\">

<head>
    <meta charset=\"UTF-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
    <title>gchessboard</title>

    <style>
        body {
            background-color: #97AC9B;
        }
    </style>

    <script type=\"module\" src=\"/static/index.js\"></script>
</head>

<body>
    <div ui-lustre-app></div>
    <div id=\"no-context-menu-wrapper\"><div gchessboard-lustre-app></div></div>
</body>

</html>
"

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- web.middleware(req, ctx)
  case wisp.path_segments(req) {
    ["request_game_with_computer"] -> {
      io.println("Requesting game with computer")
      wisp.html_response(string_builder.from_string("hello"), 200)
    }
    _ -> wisp.html_response(string_builder.from_string(html), 200)
  }
}
