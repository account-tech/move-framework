/// This module demonstrates how to create an intent with a custom action.
/// Here the action accessors are public but protected by an Intent and an Executable.
/// This means that any package can reuse this action for implementing its own intent.

module account_examples::managing_settings_composable;

use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired, Params},
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

    account.build_intent!(
        params,
        outcome, 
        b"".to_string(),
        version::current(),
        UpdateFeeIntent(),
        ctx,
        |intent, iw| {
            new_update<_, _>(intent, fee, iw);
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
        |executable, iw| do_update(executable, protocol, iw),
    );
}

/// step 5: destroy the executable with account_protocol::account::confirm_execution

/// step 6: destroy the intent to get the Expired hot potato as there is no execution left

/// step 7: delete the actions from Expired in their own module 

/// These functions are public and necessitate both a witness and a "VersionWitness" 
/// to ensure correct implementation of the intents that could be defined.
/// 
/// The action can only be instantiated within an intent.
/// And it can be accessed (and executed) only through the acquisition of an Executable.
/// 
/// This is the pattern that should be used to make actions available to other packages.

public fun new_update<Outcome, IW: drop>(
    intent: &mut Intent<Outcome>,
    fee: u64,
    intent_witness: IW,    
) {
    assert!(fee <= MAX_FEE);
    intent.add_action(UpdateFeeAction { fee }, intent_witness);
}

public fun do_update<Outcome: store, IW: drop>(
    executable: &mut Executable<Outcome>,
    protocol: &mut Protocol,
    intent_witness: IW,
) {
    let update_fee: &UpdateFeeAction = executable.next_action(intent_witness);
    protocol.fee = update_fee.fee;
}
    
public fun delete_update(expired: &mut Expired) {
    let UpdateFeeAction { .. } = expired.remove_action();
}