var HDWalletProvider = require("truffle-hdwallet-provider");
var mnemonic = "candy maple cake sugar pudding cream honey rich smooth crumble sweet treat";

module.exports = {
  networks: {
    development: {
      provider: function() {
        var wallet = new HDWalletProvider(mnemonic, "http://127.0.0.1:8545/", 0, 50);
        //var nonceTracker = new NonceTrackerSubprovider()
        //wallet.engine._providers.unshift(nonceTracker)
        //nonceTracker.setEngine(wallet.engine)
        return wallet
      },
      network_id: '*',
      gas: 6000000
    }
  },
  compilers: {
    solc: {
      version: "0.8.9",
      settings: {
        optimizer: {
            enabled: false,
            runs: 200
        },
        evmVersion: "constantinople"
       }
    }
  }
};