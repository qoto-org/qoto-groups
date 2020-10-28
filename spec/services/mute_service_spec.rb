require 'rails_helper'

RSpec.describe MuteService, type: :service do
  subject do
    -> { described_class.new.call(account, target_account) }
  end

  let(:account) { Fabricate(:account) }
  let(:target_account) { Fabricate(:account) }

  it 'mutes account' do
    is_expected.to change {
      account.muting?(target_account)
    }.from(false).to(true)
  end

  context 'without specifying a notifications parameter' do
    it 'mutes notifications from the account' do
      is_expected.to change {
        account.muting_notifications?(target_account)
      }.from(false).to(true)
    end
  end

  context 'with a true notifications parameter' do
    subject do
      -> { described_class.new.call(account, target_account, notifications: true) }
    end

    it 'mutes notifications from the account' do
      is_expected.to change {
        account.muting_notifications?(target_account)
      }.from(false).to(true)
    end
  end

  context 'with a false notifications parameter' do
    subject do
      -> { described_class.new.call(account, target_account, notifications: false) }
    end

    it 'does not mute notifications from the account' do
      is_expected.to_not change {
        account.muting_notifications?(target_account)
      }.from(false)
    end
  end
end
