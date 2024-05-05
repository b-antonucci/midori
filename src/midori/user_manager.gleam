import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import ids/uuid
import midori/user_manager_message.{
  type UserManagerMessage, AddGameToUser, AddUser, ConfirmUserExists,
  GetUserGame, RemoveUser,
}

pub type UserId =
  String

pub type GameId =
  String

pub type UserManagerState {
  UserManagerState(users: Dict(UserId, Option(GameId)))
}

fn handle_message(
  message: UserManagerMessage,
  state: UserManagerState,
) -> actor.Next(UserManagerMessage, UserManagerState) {
  case message {
    AddUser(reply_with) -> {
      case uuid.generate_v7() {
        Ok(id) -> {
          // let new_state = UserManagerState(users: [id, ..state.users])
          let users = dict.insert(state.users, id, None)
          let new_state = UserManagerState(users: users)
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
      case dict.has_key(state.users, id) {
        True -> {
          let new_state = UserManagerState(users: dict.delete(state.users, id))
          process.send(reply_with, Ok(Nil))
          actor.continue(new_state)
        }
        False -> {
          process.send(reply_with, Error("User not found"))
          actor.continue(state)
        }
      }
    }
    AddGameToUser(reply_with, user_id, game_id) -> {
      case dict.get(state.users, user_id) {
        Ok(_) -> {
          let new_state =
            UserManagerState(users: dict.insert(
              state.users,
              user_id,
              Some(game_id),
            ))
          process.send(reply_with, Ok(Nil))
          actor.continue(new_state)
        }
        Error(_) -> {
          process.send(reply_with, Error("User not found"))
          actor.continue(state)
        }
      }
    }
    GetUserGame(reply_with, id) -> {
      case dict.get(state.users, id) {
        Ok(game) -> {
          process.send(reply_with, Ok(game))
          actor.continue(state)
        }
        Error(_) -> {
          process.send(reply_with, Error("User not found"))
          actor.continue(state)
        }
      }
    }
    ConfirmUserExists(reply_with, id) -> {
      case dict.has_key(state.users, id) {
        True -> {
          process.send(reply_with, Ok(Nil))
          actor.continue(state)
        }
        False -> {
          process.send(reply_with, Error("User not found"))
          actor.continue(state)
        }
      }
    }
  }
}

pub fn start_user_manager() {
  actor.start(UserManagerState(users: dict.new()), handle_message)
}
