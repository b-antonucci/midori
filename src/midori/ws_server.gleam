import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import mist.{type WebsocketConnection}

import gleam/dict
import midori/user_id.{type UserId}
import midori/ws_server_message.{
  type WebsocketServerMessage, AddConnection, CheckForExistingConnection,
  RemoveConnection, Send,
}

pub type WebsocketServerState {
  WebsocketServerState(connections: dict.Dict(UserId, WebsocketConnection))
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
    CheckForExistingConnection(client, user_id) -> {
      let exists = dict.has_key(state.connections, user_id)
      process.send(client, exists)
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
