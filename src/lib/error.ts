class UnwrapError extends Error {
  type: 'Expected Ok got Error' | 'Expected Err got Ok' | 'Expected Some got None';
  monadType: 'result' | 'option';

  constructor(
    message: string,
    monadType: 'result' | 'option',
    type: 'Expected Ok got Error' | 'Expected Err got Ok' | 'Expected Some got None',
  ) {
    super(message);
    this.type = type;
    this.monadType = monadType;
    this.name = 'UnwrapError';
  }
}

export { UnwrapError };
