import gleam/erlang/process.{type Subject}

import gleam/otp/actor
import mist.{type WebsocketConnection}

import gleam/dict
import midori/game_id.{type GameId}

// TODO: These should all be sync calls instead of async
pub type WebsocketServerMessage {
  Send(recipient: GameId, message: String)
  AddConnection(recipient: GameId, connection: WebsocketConnection)
  RemoveConnection(recipient: GameId)
}

pub type WebsocketServerState {
  WebsocketServerState(connections: dict.Dict(GameId, WebsocketConnection))
}

fn handle_message(
  message: WebsocketServerMessage,
  state: WebsocketServerState,
) -> actor.Next(WebsocketServerMessage, WebsocketServerState) {
  let state = case message {
    Send(recipient, message) -> {
      let assert Ok(conn) = dict.get(state.connections, recipient)
      let assert Ok(_) = mist.send_text_frame(conn, message)
      state
    }
    AddConnection(recipient, connection) -> {
      let connections = dict.insert(state.connections, recipient, connection)
      WebsocketServerState(connections)
    }
    RemoveConnection(recipient) -> {
      let connections = dict.delete(state.connections, recipient)
      WebsocketServerState(connections)
    }
  }
  actor.continue(state)
}

pub fn start_ws_server() -> Result(Subject(WebsocketServerMessage), _) {
  let actor =
    actor.start(WebsocketServerState(connections: dict.new()), handle_message)
  actor
}
