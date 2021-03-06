# Starknet AMM Tutorial
https://starknet.io/docs/hello_starknet/amm.html#amm-starknet

### Compile
```
$ starknet-compile amm_sample.cairo \
    --output amm_sample_compiled.json \
    --abi amm_sample_abi.json
```

### Get token balances for each pool
```
$ starknet call \
    --address ${AMM_ADDRESS} \
    --abi amm_sample_abi.json \
    --function get_pool_token_balance \
    --inputs 1

$ starknet call \
    --address ${AMM_ADDRESS} \
    --abi amm_sample_abi.json \
    --function get_pool_token_balance \
    --inputs 2
```

### Add demo tokens for the account, 1000 of each
```
$ starknet invoke \
    --address ${AMM_ADDRESS} \
    --abi amm_sample_abi.json \
    --function add_demo_token \
    --inputs ${ACCOUNT_ID} 1000 1000
```

### Get account balance for token 1 and 2 (A and B) 
Should start with 1000 for A and 1000 for B

```
$ starknet call \
    --address ${AMM_ADDRESS} \
    --abi amm_sample_abi.json \
    --function get_account_token_balance \
    --inputs ${ACCOUNT_ID} 1
```

### Perform the swap
```
$ starknet invoke \
    --address ${AMM_ADDRESS} \
    --abi amm_sample_abi.json \
    --function swap \
    --inputs ${ACCOUNT_ID} 1 500
```

### Query for updated balance
If you run `get_account_token_balance` again, you should now have 500 for token 1, and 1000 + b for 2 (where b is based on the constant product formula)
`b = (y * a) + (x + a)`

```
$ starknet call \
    --address ${AMM_ADDRESS} \
    --abi amm_sample_abi.json \
    --function get_account_token_balance \
    --inputs ${ACCOUNT_ID} 1
```