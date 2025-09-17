module account_actions::kiosk_intents;

// === Imports ===

use std::string::String;
use sui::{
    kiosk::{Kiosk, KioskOwnerCap},
    transfer_policy::{TransferPolicy, TransferRequest},
};
use account_protocol::{
    account::{Account, Auth},
    intents::Params,
    executable::Executable,
    intent_interface,
};
use account_actions::{
    kiosk as acc_kiosk,
    version,
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const ENoLock: u64 = 0;
const ENftsPricesNotSameLength: u64 = 1;

// === Structs ===

/// Intent Witness defining the intent to take nfts from a kiosk managed by a account to another kiosk.
public struct TakeNftsIntent() has copy, drop;
/// Intent Witness defining the intent to list nfts in a kiosk managed by a account.
public struct ListNftsIntent() has copy, drop;

// === Public functions ===

/// Creates a TakeNftsIntent and adds it to an Account.
public fun request_take_nfts<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    kiosk_name: String,
    nft_ids: vector<ID>,
    recipient: address,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    assert!(acc_kiosk::has_lock(account, kiosk_name), ENoLock);

    account.build_intent!(
        params,
        outcome, 
        kiosk_name,
        version::current(),
        TakeNftsIntent(),
        ctx,
        |intent, iw| nft_ids.do!(|nft_id| acc_kiosk::new_take(intent, kiosk_name, nft_id, recipient, iw))
    );
}

/// Executes a TakeNftsIntent, takes nfts from a kiosk managed by a account to another kiosk. Can be looped over.
public fun execute_take_nfts<Config, Outcome: store, Nft: key + store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    account_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<Nft>,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    account.process_intent!(
        executable,
        version::current(),
        TakeNftsIntent(),
        |executable, iw| acc_kiosk::do_take<_, _, Nft, _>(
            executable, 
            account, 
            account_kiosk, 
            recipient_kiosk, 
            recipient_cap, 
            policy, 
            version::current(), 
            iw, 
            ctx
        ),
    )
}

/// Creates a ListNftsIntent and adds it to an Account.
public fun request_list_nfts<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    kiosk_name: String,
    nft_ids: vector<ID>,
    prices: vector<u64>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(acc_kiosk::has_lock(account, kiosk_name), ENoLock);
    assert!(nft_ids.length() == prices.length(), ENftsPricesNotSameLength);

    account.build_intent!(
        params,
        outcome,
        kiosk_name,
        version::current(),
        ListNftsIntent(),
        ctx,
        |intent, iw| nft_ids.zip_do!(prices, |nft_id, price| acc_kiosk::new_list(intent, kiosk_name, nft_id, price, iw))
    );
}

/// Executes a ListNftsIntent, lists nfts in a kiosk managed by a account. Can be looped over.
public fun execute_list_nfts<Config, Outcome: store, Nft: key + store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    kiosk: &mut Kiosk,
) {
    account.process_intent!(
        executable,
        version::current(),
        ListNftsIntent(),
        |executable, iw| acc_kiosk::do_list<_, _, Nft, _>(executable, account, kiosk, version::current(), iw),
    );
}