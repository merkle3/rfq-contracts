.PHONY: test

test:
	forge test -vvv

deploy: 
	 forge create --rpc-url ${RPC} \
		--constructor-args "${OWNER}" \
		--private-key ${PK} \
		--etherscan-api-key ${ETHERSCAN} \
		--verify \
		--verifier-url https://api.etherscan.io/api \
		src/MerkleOrderSettler.sol:MerkleOrderSettler

# cast abi-encode "constructor(address)" "${OWNER}"
verify:
	forge verify-contract \
	0x283bc597bc9ff7180d1d9f214b8ca71d98a6d360 \
	MerkleOrderSettler \
	--constructor-args "$(cast abi-encode "constructor(address)" "${OWNER}")" \
	--etherscan-api-key ${ETHERSCAN} \
	--verifier-url https://api.etherscan.io/api