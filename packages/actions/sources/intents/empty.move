module account_actions::empty_intents;

// === Imports ===

use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    intents::Params,
    intent_interface,
};
use account_actions::version;

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Structs ===    

/// Intent Witness defining an intent with no action.
public struct EmptyIntent() has copy, drop;

// === Public functions ===

/// Creates an EmptyIntent and adds it to an Account.
public fun request_empty<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    ctx: &mut TxContext
) {
    account.verify(auth);

    account.build_intent!(
        params,
        outcome, 
        b"".to_string(),
        version::current(),
        EmptyIntent(),
        ctx,
        |_intent, _iw| {},
    );
}

/// Executes an EmptyIntent (to be able to delete it)
public fun execute_empty<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
) {
    account.process_intent!(
        executable, 
        version::current(), 
        EmptyIntent(), 
        |_executable, _iw| {},
    )
}