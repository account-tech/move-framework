module account_actions::currency_intents;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::{
    transfer::Receiving,
    coin::Coin,
    coin_registry::Currency,
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    intents::Params,
    owned,
    intent_interface,
};
use account_actions::{
    transfer as acc_transfer,
    vesting,
    version,
    currency,
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const EAmountsRecipentsNotSameLength: u64 = 0;
const EMaxSupply: u64 = 1;
const ENoLock: u64 = 2;
const ECannotUpdateName: u64 = 3;
const ECannotUpdateDescription: u64 = 4;
const ECannotUpdateIcon: u64 = 5;
const EMintDisabled: u64 = 6;
const EBurnDisabled: u64 = 7;

// === Structs ===

/// Intent Witness defining the intent to disable one or more permissions.
public struct DisableRulesIntent() has copy, drop;
/// Intent Witness defining the intent to update the Currency metadata associated with a locked MetadataCap.
public struct UpdateMetadataIntent() has copy, drop;
/// Intent Witness defining the intent to transfer a minted coin.
public struct MintAndTransferIntent() has copy, drop;
/// Intent Witness defining the intent to pay from a minted coin.
public struct MintAndVestIntent() has copy, drop;
/// Intent Witness defining the intent to burn coins from the account using a locked TreasuryCap.
public struct WithdrawAndBurnIntent() has copy, drop;

// === Public functions ===

/// Creates a DisableRulesIntent and adds it to an Account.
public fun request_disable_rules<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    mint: bool,
    burn: bool,
    update_name: bool,
    update_description: bool,
    update_icon: bool,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    assert!(currency::has_treasury_cap<_, CoinType>(account), ENoLock);

    account.build_intent!(
        params,
        outcome,
        type_name_to_string<CoinType>(),
        version::current(),
        DisableRulesIntent(),
        ctx,
        |intent, iw| currency::new_disable<_, CoinType, _>(
            intent, mint, burn, update_name, update_description, update_icon, iw
        ),
    );
}

/// Executes a DisableRulesIntent, disables rules for the coin forever.
public fun execute_disable_rules<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
) {
    account.process_intent!(
        executable,
        version::current(),
        DisableRulesIntent(),
        |executable, iw| currency::do_disable<_, _, CoinType, _>(executable, account, version::current(), iw)
    );
}

/// Creates an UpdateMetadataIntent and adds it to an Account.
public fun request_update_metadata<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    md_name: Option<String>,
    md_description: Option<String>,
    md_icon_url: Option<String>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    let rules = currency::borrow_rules<_, CoinType>(account);
    if (!rules.can_update_name()) assert!(md_name.is_none(), ECannotUpdateName);
    if (!rules.can_update_description()) assert!(md_description.is_none(), ECannotUpdateDescription);
    if (!rules.can_update_icon()) assert!(md_icon_url.is_none(), ECannotUpdateIcon);

    account.build_intent!(
        params,
        outcome,
        type_name_to_string<CoinType>(),
        version::current(),
        UpdateMetadataIntent(),
        ctx,
        |intent, iw| currency::new_update<_, CoinType, _>(
            intent, md_name, md_description, md_icon_url, iw
        ),
    );
}

/// Executes an UpdateMetadataIntent, updates the Currency metadata.
public fun execute_update_metadata<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    currency_value: &mut Currency<CoinType>,
) {
    account.process_intent!(
        executable,
        version::current(),
        UpdateMetadataIntent(),
        |executable, iw| currency::do_update<_, _, CoinType, _>(executable, account, currency_value, version::current(), iw)
    );
}

/// Creates a MintAndTransferIntent and adds it to an Account.
public fun request_mint_and_transfer<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(amounts.length() == recipients.length(), EAmountsRecipentsNotSameLength);

    let rules = currency::borrow_rules<_, CoinType>(account);
    assert!(rules.can_mint(), EMintDisabled);
    let sum = amounts.fold!(0, |sum, amount| sum + amount);
    if (rules.max_supply().is_some()) assert!(sum <= *rules.max_supply().borrow(), EMaxSupply);

    account.build_intent!(
        params,
        outcome,
        type_name_to_string<CoinType>(),
        version::current(),
        MintAndTransferIntent(),
        ctx,
        |intent, iw| amounts.zip_do!(recipients, |amount, recipient| {
            currency::new_mint<_, CoinType, _>(intent, amount, iw);
            acc_transfer::new_transfer(intent, recipient, iw);
        })
    );
}

/// Executes a MintAndTransferIntent, sends managed coins. Can be looped over.
public fun execute_mint_and_transfer<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        MintAndTransferIntent(),
        |executable, iw| {
            let coin = currency::do_mint<_, _, CoinType, _>(executable, account, version::current(), iw, ctx);
            acc_transfer::do_transfer(executable, coin, iw);
        }
    );
}

/// Creates a MintAndVestIntent and adds it to an Account.
public fun request_mint_and_vest<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    total_amount: u64,
    start_timestamp: u64,
    end_timestamp: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    let rules = currency::borrow_rules<_, CoinType>(account);
    assert!(rules.can_mint(), EMintDisabled);
    if (rules.max_supply().is_some()) assert!(total_amount <= *rules.max_supply().borrow(), EMaxSupply);

    account.build_intent!(
        params,
        outcome,
        type_name_to_string<CoinType>(),
        version::current(),
        MintAndVestIntent(),
        ctx,
        |intent, iw| {
            currency::new_mint<_, CoinType, _>(intent, total_amount, iw);
            vesting::new_vest(intent, start_timestamp, end_timestamp, recipient, iw);
        }
    );
}

/// Executes a MintAndVestIntent, sends managed coins and creates a vesting.
public fun execute_mint_and_vest<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        MintAndVestIntent(),
        |executable, iw| {
            let coin = currency::do_mint<_, _, CoinType, _>(executable, account, version::current(), iw, ctx);
            vesting::do_vest(executable, coin, iw, ctx);
        }
    );
}

/// Creates a WithdrawAndBurnIntent and adds it to an Account.
public fun request_withdraw_and_burn<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    amount: u64,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    let rules = currency::borrow_rules<_, CoinType>(account);
    assert!(rules.can_burn(), EBurnDisabled);

    intent_interface::build_intent!(
        account,
        params,
        outcome,
        type_name_to_string<CoinType>(),
        version::current(),
        WithdrawAndBurnIntent(),
        ctx,
        |intent, iw| {
            owned::new_withdraw_coin<_, _, CoinType, _>(intent, account, amount, iw);
            currency::new_burn<_, CoinType, _>(intent, amount, iw);
        }
    );
}

/// Executes a WithdrawAndBurnIntent, burns a coin owned by the account.
public fun execute_withdraw_and_burn<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    coins: vector<Receiving<Coin<CoinType>>>,
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndBurnIntent(),
        |executable, iw| {
            let coin = owned::do_withdraw_coin(executable, account, coins, iw, ctx);
            currency::do_burn(executable, account, coin, version::current(), iw);
        }
    );
}

// === Private functions ===

fun type_name_to_string<T>(): String {
    type_name::with_defining_ids<T>().into_string().to_string()
}
