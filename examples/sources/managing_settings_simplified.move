/// This module demonstrates how to create an intent with a custom action.
/// Here there is no action interface as the action is directly handled as part of the intent.
/// This means that the action cannot be reused in another module.

module account_examples::managing_settings_simplified;

use account_protocol::{
    account::{Account, Auth},
    intents::{Expired, Params},
    executable::Executable,
    intent_interface,
};
use account_examples::version;

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Constants ===

const MAX_FEE: u64 = 10000; // 100%

// === Structs ===

/// Intent structs must have copy and drop only
public struct UpdateFeeIntent() has copy, drop;

/// Action structs must have store only 
public struct UpdateFeeAction has store {
    fee: u64,
}

/// Represents the 3rd party protocol and its fee
public struct Protocol has key {
    id: UID,
    // add bunch of fields
    fee: u64,
}

// === Public functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(Protocol {
        id: object::new(ctx),
        fee: 0,
    });
}    

/*
* the rest of the protocol implementation 
* { ... }
*/

// === Public functions ===

/// step 1: request to update the fee
public fun request_update_fee<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    fee: u64,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(fee <= MAX_FEE);

    account.build_intent!(
        params,
        outcome, 
        "",
        version::current(),
        UpdateFeeIntent(),
        ctx,
        |intent, iw| {
            intent.add_action(UpdateFeeAction { fee }, iw);
        },
    );
}

/// step 2: resolve the intent according to the account config
/// step 3: execute the proposal and return the action (package::account_config::execute_intent)

/// step 4: execute the intent using the Executable
public fun execute_update_fee<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    protocol: &mut Protocol,
) {
    account.process_intent!(
        executable, 
        version::current(), 
        UpdateFeeIntent(), 
        |executable, iw| {
            let update_fee: &UpdateFeeAction = executable.next_action(iw);
            protocol.fee = update_fee.fee;
        },
    );
}

/// step 5: destroy the executable with account_protocol::account::confirm_execution

/// step 6: destroy the intent to get the Expired hot potato as there is no execution left

/// step 7: delete the actions from Expired in their own module 
public fun delete_update_fee(expired: &mut Expired) {
    let UpdateFeeAction { .. } = expired.remove_action();
}