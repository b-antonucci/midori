import gleam/erlang/process
import mist.{type Connection, type ResponseData}
import wisp
import midori/router
import midori/web.{Context}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/bytes_builder
import gleam/otp/actor
import gleam/option.{Some}
import gleam/io
import ids/uuid

pub fn main() {
  let selector = process.new_selector()

  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  // A context is constructed holding the static directory path.
  let ctx = Context(static_directory: static_directory())

  // The handle_request function is partially applied with the context to make
  // the request handler function that only takes a request.
  let handler = router.handle_request(_, ctx)

  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_builder.new()))

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        ["ws"] ->
          mist.websocket(
            request: req,
            on_init: fn() {
              let assert Ok(id) = uuid.generate_v7()
              #(id, Some(selector))
            },
            on_close: fn(_state) { io.println("goodbye!") },
            handler: handle_ws_message,
          )

        _ -> not_found
      }
    }
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  let assert Ok(_) =
    wisp.mist_handler(handler, secret_key_base)
    |> mist.new
    |> mist.port(8001)
    |> mist.start_http

  process.sleep_forever()
}

pub fn static_directory() -> String {
  // The priv directory is where we store non-Gleam and non-Erlang files,
  // including static assets to be served.
  // This function returns an absolute path and works both in development and in
  // production after compilation.
  let assert Ok(priv_directory) = wisp.priv_directory("midori")
  priv_directory <> "/static"
}

pub type MyMessage {
  Broadcast(String)
}

fn handle_ws_message(state, conn, message) {
  case message {
    mist.Text(<<"ping":utf8>>) -> {
      let assert Ok(_) = mist.send_text_frame(conn, <<"pong":utf8>>)
      actor.continue(state)
    }
    mist.Text(_) | mist.Binary(_) -> {
      actor.continue(state)
    }
    mist.Custom(Broadcast(text)) -> {
      let assert Ok(_) = mist.send_text_frame(conn, <<text:utf8>>)
      actor.continue(state)
    }
    mist.Closed | mist.Shutdown -> actor.Stop(process.Normal)
  }
}
