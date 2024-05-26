import gleam/erlang/process.{type Subject}
import midori/user_id.{type UserId}
import mist.{type WebsocketConnection}

// TODO: These should all be sync calls instead of async
pub type WebsocketServerMessage {
  Send(recipient: UserId, message: String)
  CheckForExistingConnection(reply_with: Subject(Bool), user_id: UserId)
  AddConnection(recipient: UserId, connection: WebsocketConnection)
  RemoveConnection(recipient: UserId)
}
