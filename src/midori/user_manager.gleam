import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import ids/uuid

pub type UserManagerMessage {
  AddUser(reply_with: Subject(Result(String, String)))
  RemoveUser(reply_with: Subject(Result(Nil, Nil)), id: String)
}

pub type UserManagerState {
  UserManagerState(users: List(String))
}

fn handle_message(
  message: UserManagerMessage,
  state: UserManagerState,
) -> actor.Next(UserManagerMessage, UserManagerState) {
  case message {
    AddUser(reply_with) -> {
      case uuid.generate_v7() {
        Ok(id) -> {
          let new_state = UserManagerState(users: [id, ..state.users])
          process.send(reply_with, Ok(id))
          actor.continue(new_state)
        }
        Error(e) -> {
          process.send(reply_with, Error(e))
          actor.continue(state)
        }
      }
    }
    RemoveUser(reply_with, id) -> {
      actor.continue(state)
    }
  }
}

pub fn start_user_manager() {
  actor.start(UserManagerState(users: []), handle_message)
}
