import gleam/bit_array.{base64_decode}
import gleam/bytes_builder
import gleam/dict
import gleam/dynamic.{field, string}
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request, Request, get_cookies}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{Some}
import gleam/otp/actor
import midori/bot_server
import midori/bot_server_message.{SetGameManagerSubject}
import midori/client_ws_message.{ConfirmMove, update_game_message_to_json}
import midori/game_manager
import midori/game_manager_message.{type GameManagerMessage, ApplyMove}
import midori/ping_server.{type PingServerMessage}
import midori/router
import midori/uci_move.{convert_move}
import midori/user_manager
import midori/user_manager_message.{type UserManagerMessage, GetUserGame}
import midori/web.{Context}
import midori/ws_server
import midori/ws_server_message.{
  type WebsocketServerMessage, AddConnection, RemoveConnection,
}
import mist.{type Connection, type ResponseData}
import wisp

type ConnectionState {
  ConnectionState(
    id: String,
    ping_server_subject: Subject(PingServerMessage),
    game_manager_subject: Subject(GameManagerMessage),
    ws_server_subject: Subject(WebsocketServerMessage),
    user_manager_subject: Subject(UserManagerMessage),
  )
  ConnectionErrorState
}

type ApplyMoveMessage {
  ApplyMoveMessage(move: String)
}

pub fn main() {
  let selector = process.new_selector()

  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(ws_server_subject) = ws_server.start_ws_server()
  let assert Ok(bot_server_subject) = bot_server.start_bot_server(option.None)
  let assert Ok(ping_server_subject) = ping_server.start_ping_server()
  let assert Ok(user_manager_subject) = user_manager.start_user_manager()
  let assert Ok(game_manager_subject) =
    game_manager.start_game_manager(bot_server_subject, ws_server_subject)
  process.send(bot_server_subject, SetGameManagerSubject(game_manager_subject))

  // A context is constructed holding the static directory path.
  let ctx =
    Context(
      static_directory: static_directory(),
      game_manager_subject: game_manager_subject,
      user_manager_subject: user_manager_subject,
    )

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
            on_init: fn(websocket) {
              case mist.read_body(req, 1000) {
                Ok(req_body) -> {
                  let assert Ok(encoded_user_id) =
                    dict.get(dict.from_list(get_cookies(req_body)), "user_id")
                  let assert Ok(user_id_bit_array) =
                    base64_decode(encoded_user_id)
                  let assert Ok(user_id) =
                    bit_array.to_string(user_id_bit_array)
                  let state =
                    ConnectionState(
                      user_id,
                      ping_server_subject,
                      game_manager_subject,
                      ws_server_subject,
                      user_manager_subject,
                    )
                  process.send(
                    ws_server_subject,
                    AddConnection(user_id, websocket),
                  )
                  #(state, Some(selector))
                }
                Error(_) -> {
                  #(ConnectionErrorState, Some(selector))
                }
              }
            },
            on_close: fn(state) {
              // let assert Ok(_) =
              //   process.call(
              //     state.game_manager_subject,
              //     RemoveGame(_, state.id),
              //     1000,
              //   )
              case state {
                ConnectionState(id, _, _, _, _) ->
                  process.send(ws_server_subject, RemoveConnection(id))
                ConnectionErrorState -> Nil
              }
              Nil
            },
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

fn handle_ws_message(state: ConnectionState, conn, message) {
  case state {
    ConnectionState(
      id,
      _ping_server_subject,
      game_manager_subject,
      _ws_server_subject,
      user_manager_subject,
    ) -> {
      case message {
        mist.Text("0") -> {
          // process.send(state.ping_server_subject, ping_server.Ping(conn))
          actor.continue(state)
        }
        mist.Text(ws_message) -> {
          let message_decoder =
            dynamic.decode1(ApplyMoveMessage, field("move", string))
          case json.decode(ws_message, message_decoder) {
            Ok(ApplyMoveMessage(move)) -> {
              let assert Ok(Some(game_id)) =
                process.call(user_manager_subject, GetUserGame(_, id), 1000)
              let game_manager_response =
                process.call(
                  game_manager_subject,
                  ApplyMove(_, game_id, id, convert_move(move)),
                  1000,
                )
              let update_game_message =
                ConfirmMove(move: game_manager_response.move)
              let json = update_game_message_to_json(update_game_message)

              let assert Ok(_) = mist.send_text_frame(conn, json)

              actor.continue(state)
            }
            Error(_) -> {
              actor.continue(state)
            }
          }

          actor.continue(state)
        }
        mist.Text(_) | mist.Binary(_) -> {
          actor.continue(state)
        }
        mist.Custom(Broadcast(text)) -> {
          let assert Ok(_) = mist.send_text_frame(conn, text)
          actor.continue(state)
        }
        mist.Closed | mist.Shutdown -> actor.Stop(process.Normal)
      }
    }
    ConnectionErrorState -> actor.continue(state)
  }
}
