import gleam/erlang/process.{type Subject}
import midori/game_manager_message.{type GameManagerMessage}
import midori/user_manager_message.{type UserManagerMessage}

import wisp

pub type Context {
  Context(
    static_directory: String,
    game_manager_subject: Subject(GameManagerMessage),
    user_manager_subject: Subject(UserManagerMessage),
  )
}

pub fn middleware(
  req: wisp.Request,
  ctx: Context,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(
    req,
    under: "/assets",
    from: ctx.static_directory <> "/assets",
  )
  use <- wisp.serve_static(req, under: "/static", from: ctx.static_directory)

  handle_request(req)
}
