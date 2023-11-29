import wisp.{type Request, type Response}
import gleam/string_builder
import gleam/http
import midori/web.{type Context}
import gleam/erlang/file

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
    <div data-lustre-app></div>
</body>

</html>
"

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- web.middleware(req, ctx)
  wisp.html_response(string_builder.from_string(html), 200)
}
