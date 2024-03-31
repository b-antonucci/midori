import gleam/erlang/process.{type Subject}
import mist.{type Connection, type ResponseData}
import wisp
import midori/router
import midori/uci_move.{convert_move}
import midori/web.{Context}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/bytes_builder
import gleam/otp/actor
import gleam/option.{None, Some}
import gleam/io
import gleam/list
import move.{type Move, Castle, EnPassant, Normal}
import piece.{Bishop, Knight, Queen, Rook}
import position.{to_string}
import midori/ping_server.{type PingServerMessage}
import midori/game_manager.{type ClientFormatMoveList, type GameManagerMessage}
import gleam/dynamic.{field, list, string}
import gleam/json.{array, object, string as json_string}

type State {
  State(
    id: String,
    ping_server_subject: Subject(PingServerMessage),
    game_manager_subject: Subject(GameManagerMessage),
  )
}

type ApplyMoveMessage {
  ApplyMoveMessage(move: String)
}

pub type UpdateGameMessage {
  UpdateGameMessage(moves: ClientFormatMoveList, fen: String)
}

type LegalMoves =
  List(Move)

pub fn legal_moves_to_legal_uci_moves(legal_moves: LegalMoves) -> List(String) {
  legal_moves
  |> list.map(fn(move) {
    case move {
      Normal(from, to, _captured, promotion) -> {
        let promotion_string = case promotion {
          None -> ""
          Some(promotion) ->
            case promotion.kind {
              Queen -> "q"
              Rook -> "r"
              Bishop -> "b"
              Knight -> "n"
              _ -> panic("Invalid promotion")
            }
        }

        to_string(from) <> to_string(to) <> promotion_string
      }
      Castle(from, to) -> {
        to_string(from) <> to_string(to)
      }
      EnPassant(from, to) -> {
        to_string(from) <> to_string(to)
      }
    }
  })
}

pub fn update_game_message_to_json(
  update_game_message: UpdateGameMessage,
) -> String {
  let moves = update_game_message.moves.moves
  let moves_with_json_dests =
    list.map(moves, fn(move) { #(move.0, array(move.1, of: json_string)) })
  object([
    #("moves", object(moves_with_json_dests)),
    #("fen", json_string(update_game_message.fen)),
  ])
  |> json.to_string
}

pub fn main() {
  let selector = process.new_selector()

  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(ping_server_subject) = ping_server.start_ping_server()
  let assert Ok(game_manager_subject) = game_manager.start_game_manager()

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
            on_init: fn(_websocket) {
              let id =
                process.call(game_manager_subject, game_manager.NewGame, 10)
              let state = State(id, ping_server_subject, game_manager_subject)
              #(state, Some(selector))
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

fn handle_ws_message(state: State, conn, message) {
  case message {
    mist.Text("ping") -> {
      process.send(state.ping_server_subject, ping_server.Ping(conn))
      actor.continue(state)
    }
    mist.Text(ws_message) -> {
      let message_decoder =
        dynamic.decode1(ApplyMoveMessage, field("move", string))

      case json.decode(ws_message, message_decoder) {
        Ok(ApplyMoveMessage(move)) -> {
          let game_manager_response =
            process.call(
              state.game_manager_subject,
              game_manager.ApplyMove(_, state.id, convert_move(move)),
              10,
            )
          let update_game_message =
            UpdateGameMessage(
              moves: game_manager_response.legal_moves,
              fen: game_manager_response.fen,
            )
          let json = update_game_message_to_json(update_game_message)

          let assert Ok(_) = mist.send_text_frame(conn, json)

          actor.continue(state)
        }
        Error(_) -> {
          io.println("Failed to decode message")
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
