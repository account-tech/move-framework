/// This module defines apis to transfer assets owned or managed by the account.
/// The intents can implement transfers for any action type (e.g. see owned or vault).

module account_actions::transfer;

// === Imports ===

use account_protocol::{
    account::Account,
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};

// === Structs ===

/// Action used in combination with other actions (like WithdrawAction) to transfer objects to a recipient.
public struct TransferAction has store {
    // address to transfer to
    recipient: address,
}

// === Public functions ===

/// Creates a TransferAction and adds it to an intent.
public fun new_transfer<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config>, 
    recipient: address,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.add_action(intent, TransferAction { recipient }, version_witness, intent_witness);
}

/// Processes a TransferAction and transfers an object to a recipient.
public fun do_transfer<Config, Outcome: store, T: key + store, IW: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config>, 
    object: T,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    let action = account.process_action<_, Outcome, TransferAction, _>(executable, version_witness, intent_witness);
    transfer::public_transfer(object, action.recipient);
}

/// Deletes a TransferAction from an expired intent.
public fun delete_transfer(expired: &mut Expired) {
    let TransferAction { .. } = expired.remove_action();
}
