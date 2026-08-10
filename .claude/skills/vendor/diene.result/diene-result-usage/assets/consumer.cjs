const { Ok, Opt } = require('@atomicloud/diene.result');

module.exports.consumeResult = async function consumeResult() {
  const doubled = await Ok(21)
    .map(value => value * 2)
    .unwrap();
  const present = await Opt.fromNative('value').isSome();
  return { doubled, present };
};
