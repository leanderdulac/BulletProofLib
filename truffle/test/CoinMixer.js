const CoinMixer = artifacts.require('CoinMixer')
const SimpleToken = artifacts.require('test/SimpleToken')
const RangeProofVerifier = artifacts.require("RangeProofVerifier.sol")

const should = require('chai')
  .use(require('chai-bignumber')(web3.BigNumber))
  .should()

contract('CoinMixer', ([account1, account2]) => {
  beforeEach(async () => {
     const verifier = await RangeProofVerifier.deployed()
    this.token = await SimpleToken.new()
    this.coinMixer = await CoinMixer.new([
                new web3.BigNumber('0x77da99d806abd13c9f15ece5398525119d11e11e9836b2ee7d23f6159ad87d4'),
                new web3.BigNumber('0x1485efa927f2ad41bff567eec88f32fb0a0f706588b4e41a8d587d008b7f875'),
                new web3.BigNumber('0x1b7de3dcf359928dd19f643d54dc487478b68a5b2634f9f1903c9fb78331aef'),
                new web3.BigNumber('0x2bda7d3ae6a557c716477c108be0d0f94abc6c4dc6b1bd93caccbcceaaa71d6b')
            ],
            verifier.address,
            this.token.address)
  })

  it('can make a deposit', async () => {
      const value = 1000
      const oldAccountBalance = await this.token.balanceOf(account1)
      await this.token.approve(this.coinMixer.address, value)
      await this.coinMixer.deposit(value)
      const newAccountBalance = await this.token.balanceOf(account1)
      newAccountBalance.should.be.bignumber.equal(oldAccountBalance.minus(value))
      const contractBalance = await this.token.balanceOf(this.coinMixer.address)
      contractBalance.should.be.bignumber.equal(value)
  })

  it('can withdraw unshaded deposit', async () => {
      const value = 1000
      const oldAccountBalance = await this.token.balanceOf(account1)
      await this.token.approve(this.coinMixer.address, value)
      await this.coinMixer.deposit(value)
      await this.coinMixer.withdraw(value, 0)
      const newAccountBalance = await this.token.balanceOf(account1)
      newAccountBalance.should.be.bignumber.equal(oldAccountBalance)
      const contractBalance = await this.token.balanceOf(this.coinMixer.address)
      contractBalance.should.be.bignumber.equal(0)
  })

  it('can shade deposits via transfer', async () => {
      const oldAccountBalance = await this.token.balanceOf(account1)
      await this.token.approve(this.coinMixer.address, 1000)
      await this.coinMixer.deposit(1000)
      console.log(account2)
      await this.coinMixer.transfer(
          // 500 * G + 1 * H
          account1, new web3.BigNumber('0xe37350b91dd504726a2f819bab4cd35232deda17b810f38fdd0e0413febf723'), new web3.BigNumber('0x10e6d83bc58469a3d190396f025c55b23a44926c9d3f9111ebcea33f52aca0e6'),
          // 500 * G + (q - 1) * H
          account2, new web3.BigNumber('0xe2c581d2f347386e32f3c3b25d51856f9a1faed506d691582bffdca368680b5'), new web3.BigNumber('0x2f16b30346680751b1931dbc145727c9b55424f577d481ee946eae15908f49a7')
      )
      await this.coinMixer.withdraw(500, 1)
      const balance = await this.token.balanceOf(account1)
      balance.should.be.bignumber.equal(oldAccountBalance.minus(500))
  })
})
