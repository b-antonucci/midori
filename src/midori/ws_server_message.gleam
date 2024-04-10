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
