import gleam/erlang/process
import gleam/option.{Some}
import gleam/string_builder
import midori/user_manager_message.{AddUser, ConfirmUserExists, GetUserGame}
import midori/web.{type Context}
import wisp.{type Request, type Response}

const html = "
<!DOCTYPE html>
<html lang=\"en\">

<head>
    <meta charset=\"UTF-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
    <title>shahmat.org</title>

    <style>
        body {
            background-color: #151411;
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
    ["game", _game_id] -> {
      case wisp.get_cookie(req, "user_id", wisp.PlainText) {
        Ok(user_id) -> {
          let user_check_result =
            process.call(
              ctx.user_manager_subject,
              ConfirmUserExists(_, user_id),
              1000,
            )
          case user_check_result {
            Ok(_) -> {
              let game_check_result =
                process.call(
                  ctx.user_manager_subject,
                  GetUserGame(_, user_id),
                  1000,
                )
              case game_check_result {
                Ok(Some(_game_id)) -> {
                  wisp.html_response(string_builder.from_string(html), 200)
                }
                _ -> {
                  wisp.redirect("/")
                }
              }
            }
            Error(_msg) -> {
              wisp.redirect("/")
            }
          }
        }
        Error(_msg) -> {
          wisp.redirect("/")
        }
      }
    }
    _ -> {
      case wisp.get_cookie(req, "user_id", wisp.PlainText) {
        Ok(user_id) -> {
          let user_check_result =
            process.call(
              ctx.user_manager_subject,
              ConfirmUserExists(_, user_id),
              1000,
            )

          case user_check_result {
            Ok(_) -> {
              wisp.html_response(string_builder.from_string(html), 200)
            }
            Error(_msg) -> {
              case process.call(ctx.user_manager_subject, AddUser, 1000) {
                Ok(user_id) -> {
                  wisp.html_response(string_builder.from_string(html), 200)
                  |> wisp.set_cookie(
                    req,
                    "user_id",
                    user_id,
                    wisp.PlainText,
                    60 * 60 * 24,
                  )
                }
                Error(_msg) -> {
                  wisp.html_response(string_builder.from_string("Error"), 500)
                }
              }
            }
          }
        }
        Error(_msg) -> {
          case process.call(ctx.user_manager_subject, AddUser, 1000) {
            Ok(user_id) -> {
              wisp.html_response(string_builder.from_string(html), 200)
              |> wisp.set_cookie(
                req,
                "user_id",
                user_id,
                wisp.PlainText,
                60 * 60 * 24,
              )
            }
            Error(_msg) -> {
              wisp.html_response(string_builder.from_string("Error"), 500)
            }
          }
        }
      }
    }
  }
}
