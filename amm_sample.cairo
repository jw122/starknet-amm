# SOURCE: https://github.com/starkware-libs/cairo-lang/blob/master/src/starkware/starknet/apps/amm_sample/amm_sample.cairo
%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_le, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import storage_read, storage_write

# One pool to be managed by the contract
# Implements a straightforward swap functionality (in both directions) using a simple curve
# Constant product formula: x * y = k
# Tokens managed by the AMM are tokens A and B (any type of fungible tokens)

# There are 2 dedicated fields for maintaining the state:
# 1. Pool balance: How much liquidity is available in the pool, per token
# 2. Account balances: How many tokens of each type are kept in each account

# The maximum amount of each token that belongs to the AMM.
const BALANCE_UPPER_BOUND = 2 ** 64

const TOKEN_TYPE_A = 1
const TOKEN_TYPE_B = 2

# Ensure the user's balances are much smaller than the pool's balance.
const POOL_UPPER_BOUND = 2 ** 30
const ACCOUNT_BALANCE_BOUND = 1073741  # 2**30 // 1000.

# In StarkNet, the programmatic model for storage is a simple key/value store.

# Pool balance: A mapping between token type and the balance available in the pool for that token type
@storage_var
func pool_balance(token_type : felt) -> (balance : felt):
end

# Account balances: A mapping between the account id and token type, to the balance avaialble in that account for the given token type
@storage_var
func account_balance(account_id : felt, token_type : felt) -> (balance : felt):
end

# Function that allows us to modify the balance of a given token type in a given account
# We pass in some implicit arguments, necessary for the assertion and storage operations
func modify_account_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account_id : felt, token_type : felt, amount : felt):
    # Retrieve the existing balance
    let (current_balance) = account_balance.read(account_id, token_type)

    # Calculate the new balance
    tempvar new_balance = current_balance + amount

    # Assert the new balance is not negative, and is less than or equal to the upper bound
    assert_nn_le(new_balance, BALANCE_UPPER_BOUND - 1)

    # Update the new balance for this account
    account_balance.write(account_id=account_id, token_type=token_type, value=new_balance)
    return ()
end

# Allow user to read the balance of an account
@view
func get_account_token_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account_id : felt, token_type : felt) -> (balance : felt):
    return account_balance.read(account_id, token_type)
end

# Asserts before setting that the balance does not exceed the upper bound.
func set_pool_token_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        token_type : felt, balance : felt):
    assert_nn_le(balance, BALANCE_UPPER_BOUND - 1)
    pool_balance.write(token_type, balance)
    return ()
end

@view
func get_pool_token_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        token_type : felt) -> (balance : felt):
    return pool_balance.read(token_type)
end

# Swapping Tokens
# This is the primary functionality of the contract

# Business logic for the swap
# 1. Retrieve the amount of tokens available in the pool, per token type
# 2. Calculate the amount of tokens of the opposite type to be received by the pool
# 3. Update the account balances for both tokens, as well as the pool's balances
func do_swap{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account_id : felt, token_from : felt, token_to : felt, amount_from : felt) -> (
        amount_to : felt):
    alloc_locals

    # Get pool balance
    let (local amm_from_balance) = get_pool_token_balance(token_type=token_from)
    let (local amm_to_balance) = get_pool_token_balance(token_type=token_to)

    # Calculate swap amount
    let (local amount_to, _) = unsigned_div_rem(
        amm_to_balance * amount_from, amm_from_balance + amount_from)

    # Update token_from balance
    modify_account_balance(account_id=account_id, token_type=token_from, amount=-amount_from)
    set_pool_token_balance(token_type=token_from, balance=amm_from_balance + amount_from)

    # Update token_to balance
    modify_account_balance(account_id=account_id, token_type=token_to, amount=amount_to)
    set_pool_token_balance(token_type=token_to, balance=amm_to_balance - amount_to)
    return (amount_to=amount_to)
end

func get_opposite_token(token_type : felt) -> (t : felt):
    if token_type == TOKEN_TYPE_A:
        return (TOKEN_TYPE_B)
    else:
        return (TOKEN_TYPE_A)
    end
end

# Swaps tokens between the given account and the pool.
# Receives as input the account id, token type, and an amount of the token to be swapped
@external
func swap{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account_id : felt, token_from : felt, amount_from : felt) -> (amount_to : felt):
    # Verify that the token type is a valid token by asserting that it is equal to one of the pool's token types
    # token_from is either TOKEN_TYPE_A or TOKEN_TYPE_B
    assert (token_from - TOKEN_TYPE_A) * (token_from - TOKEN_TYPE_B) = 0

    # The amount requested to be swapped is valid (does not exceed upper bound)
    assert_nn_le(amount_from, BALANCE_UPPER_BOUND)

    # Check that the account has enough funds to swap
    let (account_from_balance) = get_account_token_balance(
        account_id=account_id, token_type=token_from)
    assert_le(amount_from, account_from_balance)

    # Execute the actual swap
    let (token_to) = get_opposite_token(token_type=token_from)
    let (amount_to) = do_swap(
        account_id=account_id, token_from=token_from, token_to=token_to, amount_from=amount_from)

    return (amount_to=amount_to)
end

# Adds demo tokens to the given account.
@external
func add_demo_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account_id : felt, token_a_amount : felt, token_b_amount : felt):
    # Make sure the account's balance is much smaller than pool init balance
    assert_nn_le(token_a_amount, ACCOUNT_BALANCE_BOUND - 1)
    assert_nn_le(token_b_amount, ACCOUNT_BALANCE_BOUND - 1)

    modify_account_balance(account_id=account_id, token_type=TOKEN_TYPE_A, amount=token_a_amount)
    modify_account_balance(account_id=account_id, token_type=TOKEN_TYPE_B, amount=token_b_amount)

    return ()
end

# Initialize the AMM
# We don't have contract interaction and liquidity providers in this version
# We will define how to initialize the AMM (liquidity pool and some account balances)
@external
func init_pool{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        token_a : felt, token_b : felt):
    # This function takes in balances for tokens A,B and sets them using set_pool_token_balance
    # The POOL_UPPER_BOUND is a constant defined to prevent overflows
    assert_nn_le(token_a, POOL_UPPER_BOUND - 1)
    assert_nn_le(token_b, POOL_UPPER_BOUND - 1)

    set_pool_token_balance(token_type=TOKEN_TYPE_A, balance=token_a)
    set_pool_token_balance(token_type=TOKEN_TYPE_B, balance=token_b)

    return ()
end
