require 'rails_helper'

RSpec.describe ScsbImportFullJob do
  it 'creates an event' do
    allow(Scsb::PartnerUpdates).to receive(:full)
    expect { described_class.perform_now }.to change { Event.count }.by(1)
    expect(Event.last.dump.dump_type.constant).to eq 'PARTNER_RECAP_FULL'
    expect(Scsb::PartnerUpdates).to have_received(:full)
  end
end
