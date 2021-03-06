const { ApiPromise, WsProvider } = require('@polkadot/api')
const fastifyPlugin = require('fastify-plugin')

const { SUBSTRATE_URI } = require('../environment')

const polkadotConnector = async (server, options = {}) => {
  const wsProvider = new WsProvider(SUBSTRATE_URI)
  const api = await ApiPromise.create({ provider: wsProvider })
  server.decorate('polkadotConnector', api)
}

module.exports = fastifyPlugin(polkadotConnector)
