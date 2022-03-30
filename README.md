## other 
> oracle code refer to [uiniswap v2 oracles ](https://docs.uniswap.org/protocol/V2/concepts/core-concepts/oracles)


## process

``` 
1 deploy st,lj,dai token,
2 add st-dai , lj-dai pair to uniswap v2
3 deploy oracle
4 add tracking price pair to oracle
5 wait min time and update oracle data, we must timing update this price
6 deploy staking contract
7 add lj-pair and stake st token 
8 approve lj-dai to staking contract
9 stake
10 unstake
```

### test 
```
npm i && npm run test
```