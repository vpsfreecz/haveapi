const { expect } = require('chai');

function loadHaveAPI() {
  delete require.cache[require.resolve('../dist/haveapi-client.js')];
  return require('../dist/haveapi-client.js');
}

describe('HaveAPI JS client query encoding', () => {
  it('encodes query parameter components', () => {
    const HaveAPI = loadHaveAPI();
    const client = new HaveAPI.Client('https://api.example', {});
    const attackerValue = 'alice&_meta[includes]=group__secret';
    const marker = 'a=b?c#d';
    const url = client.addParamsToQuery(
      'https://api.example/v1/users',
      'user',
      {
        name: attackerValue,
        marker
      }
    );
    const parsed = new URL(url);

    expect(parsed.searchParams.get('user[name]')).to.equal(attackerValue);
    expect(parsed.searchParams.get('user[marker]')).to.equal(marker);
    expect(parsed.searchParams.has('_meta[includes]')).to.equal(false);
    expect(parsed.hash).to.equal('');
    expect(url).to.contain('user[name]=alice%26_meta%5Bincludes%5D%3Dgroup__secret');
    expect(url).to.contain('user[marker]=a%3Db%3Fc%23d');
  });
});
