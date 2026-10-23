require 'spec_helper'
require_relative '../integration/run'

describe RustClientIntegration do
  let(:msrv_cargo) { '/fixture/rust-1.95/bin/cargo' }
  let(:msrv_rustc) { '/fixture/rust-1.95/bin/rustc' }
  let(:manifest) { '/fixture/crate/Cargo.toml' }

  before do
    stub_const('ENV', { 'HAVEAPI_RUST_MSRV_CARGO' => msrv_cargo, 'HAVEAPI_RUST_MSRV_RUSTC' => msrv_rustc })
    allow(Open3).to receive(:capture2).with(msrv_rustc, '--version').and_return(['rustc 1.95.0', instance_double(Process::Status, success?: true)])
    allow(described_class).to receive(:system).and_return(true)
  end

  it 'checks the generated library naming lint using distinct selected toolchains' do
    described_class.lint_generated_names('/fixture/crate')
    expect(described_class).to have_received(:system).with('cargo', 'generate-lockfile', '--manifest-path', manifest)
    expect(described_class).to have_received(:system).with(
      {}, 'cargo', 'rustc', '--locked', '--manifest-path', manifest, '--lib', '--all-features', '--', '-D', 'non_snake_case'
    )
    expect(described_class).to have_received(:system).with(
      { 'RUSTC' => msrv_rustc }, msrv_cargo, 'rustc', '--locked', '--manifest-path', manifest,
      '--lib', '--all-features', '--', '-D', 'non_snake_case'
    )
  end

  it 'refuses a substituted compiler before Cargo starts' do
    ENV['RUSTC_WRAPPER'] = '/fixture/unexpected-wrapper'
    expect { described_class.lint_generated_names('/fixture/crate') }.to raise_error(RuntimeError, /compiler overrides/)
    expect(described_class).not_to have_received(:system)
  end

  it 'fails on the development lint before attempting the MSRV compile' do
    allow(described_class).to receive(:system).with({}, 'cargo', 'rustc', '--locked', '--manifest-path', manifest,
                                                    '--lib', '--all-features', '--', '-D', 'non_snake_case').and_return(false)
    expect { described_class.lint_generated_names('/fixture/crate') }.to raise_error(RuntimeError, /scoped naming lint/)
    expect(described_class).not_to have_received(:system).with({ 'RUSTC' => msrv_rustc }, anything, any_args)
  end

  it 'refuses a different purported MSRV version before Cargo starts' do
    allow(Open3).to receive(:capture2).with(msrv_rustc, '--version').and_return(['rustc 1.99.0', instance_double(Process::Status, success?: true)])
    expect { described_class.lint_generated_names('/fixture/crate') }.to raise_error(RuntimeError, /must be 1.95/)
    expect(described_class).not_to have_received(:system)
  end
end
