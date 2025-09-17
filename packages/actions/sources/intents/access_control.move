module account_actions::access_control_intents;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    intents::Params,
    intent_interface,
};
use account_actions::{
    access_control as ac,
    version,
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const ENoLock: u64 = 0;

// === Structs ===    

/// Intent Witness defining the intent to borrow an access cap.
public struct BorrowCapIntent() has copy, drop;

// === Public functions ===

/// Creates a BorrowCapIntent and adds it to an Account.
public fun request_borrow_cap<Config, Outcome: store, Cap>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(ac::has_lock<_, Cap>(account), ENoLock);

    account.build_intent!(
        params,
        outcome, 
        type_name_to_string<Cap>(),
        version::current(),
        BorrowCapIntent(),
        ctx,
        |intent, iw| {
            ac::new_borrow<_, Cap, _>(intent, iw);
            ac::new_return<_, Cap, _>(intent, iw);
        },
    );
}

/// Executes a BorrowCapIntent, returns a cap and a hot potato.
public fun execute_borrow_cap<Config, Outcome: store, Cap: key + store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
): Cap {
    account.process_intent!(
        executable, 
        version::current(), 
        BorrowCapIntent(), 
        |executable, iw| ac::do_borrow(executable, account, version::current(), iw),
    )
}

/// Completes a BorrowCapIntent, destroys the executable and returns the cap to the account if the matching hot potato is returned.
public fun execute_return_cap<Config, Outcome: store, Cap: key + store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    cap: Cap,
) {
    account.process_intent!(
        executable, 
        version::current(), 
        BorrowCapIntent(), 
        |executable, iw| ac::do_return(executable, account, cap, version::current(), iw),
    )
}

// === Private functions ===

fun type_name_to_string<T>(): String {
    type_name::with_defining_ids<T>().into_string().to_string()
}