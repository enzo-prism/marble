require 'minitest/autorun'
require_relative '../verify_intent_authentication'

class IntentAuthenticationTest < Minitest::Test
  def metadata
    { 'actions' => MarbleIntentAuthentication::REQUIRED_ACTIONS.to_h do |name|
      [name, { 'authenticationPolicy' => 1, 'isAuthPolExplicit' => true }]
    end }
  end

  def test_accepts_authenticated_actions_and_stronger_local_authentication
    data = metadata
    data['actions']['FindWorkoutsIntent']['authenticationPolicy'] = 2
    MarbleIntentAuthentication.verify(data)
  end

  def test_rejects_missing_or_always_allowed_actions
    missing = metadata
    missing['actions'].delete('FinishWorkoutIntent')
    assert_raises(KeyError) { MarbleIntentAuthentication.verify(missing) }
    allowed = metadata
    allowed['actions']['FinishWorkoutIntent']['authenticationPolicy'] = 0
    assert_raises(RuntimeError) { MarbleIntentAuthentication.verify(allowed) }
  end

  def test_rejects_implicit_policy_even_with_nonzero_value
    data = metadata
    data['actions']['StartWorkoutIntent']['isAuthPolExplicit'] = false
    assert_raises(RuntimeError) { MarbleIntentAuthentication.verify(data) }
  end
end
