/// This module defines apis to transfer assets owned or managed by the account.
/// The intents can implement transfers for any action type (e.g. see owned or vault).

module account_actions::transfer;

// === Imports ===

use account_protocol::{
    intents::{Expired, Intent},
    executable::Executable,
};

// === Structs ===

/// Action used in combination with other actions (like WithdrawAction) to transfer objects to a recipient.
public struct TransferAction has store {
    // address to transfer to
    recipient: address,
}

// === Public functions ===

/// Creates a TransferAction and adds it to an intent.
public fun new_transfer<Outcome, IW: drop>(
    intent: &mut Intent<Outcome>,
    recipient: address,
    intent_witness: IW,
) {
    intent.add_action(TransferAction { recipient }, intent_witness);
}

/// Processes a TransferAction and transfers an object to a recipient.
public fun do_transfer<Outcome: store, T: key + store, IW: drop>(
    executable: &mut Executable<Outcome>, 
    object: T,
    intent_witness: IW,
) {
    let action: &TransferAction = executable.next_action(intent_witness);
    transfer::public_transfer(object, action.recipient);
}

/// Deletes a TransferAction from an expired intent.
public fun delete_transfer(expired: &mut Expired) {
    let TransferAction { .. } = expired.remove_action();
}
