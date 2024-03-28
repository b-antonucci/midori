import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import mist.{type WebsocketConnection}

pub type PingServerMessage {
  Ping(conn: WebsocketConnection)
}

fn handle_message(
  message: PingServerMessage,
  state: String,
) -> actor.Next(PingServerMessage, String) {
  case message {
    Ping(conn) -> {
      process.sleep(10_000)
      let assert Ok(_) = mist.send_text_frame(conn, "pong")
    }
  }
  actor.continue(state)
}

pub fn start_ping_server() -> Result(Subject(PingServerMessage), _) {
  let actor = actor.start("Ping Pong", handle_message)
  actor
}
