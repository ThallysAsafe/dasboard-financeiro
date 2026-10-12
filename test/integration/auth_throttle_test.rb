require "test_helper"

class AuthThrottleTest < ActionDispatch::IntegrationTest
  # A janela do Rack::Attack é fixa (alinhada ao relógio): sem congelar o
  # tempo, um teste que cruza a virada do minuto divide o contador e falha.
  setup do
    Rack::Attack.cache.store.clear
    travel_to Time.current.beginning_of_hour + 10.seconds
  end

  teardown { Rack::Attack.cache.store.clear }

  def login(email, password = "errada", ip: "10.0.0.1")
    post "/api/v1/auth/login", params: { email: email, password: password },
                               headers: { "REMOTE_ADDR" => ip }
  end

  test "REST: a 6ª tentativa de login do mesmo IP recebe 429" do
    5.times { |i| login("pessoa#{i}@exemplo.com"); assert_response :unauthorized }

    login("outra@exemplo.com")
    assert_response :too_many_requests
    assert_equal AuthThrottle::MESSAGE, response.parsed_body["error"]
  end

  test "REST: limita por e-mail mesmo vindo de IPs diferentes" do
    5.times { |i| login("dois@exemplo.com", ip: "10.0.1.#{i}"); assert_response :unauthorized }

    login("dois@exemplo.com", ip: "10.0.2.1")
    assert_response :too_many_requests
  end

  test "REST: o e-mail é normalizado (maiúsculas e espaços não burlam o limite)" do
    5.times { |i| login(i.even? ? "DOIS@exemplo.com" : " dois@exemplo.com ", ip: "10.0.3.#{i}") }

    login("dois@exemplo.com", ip: "10.0.3.9")
    assert_response :too_many_requests
  end

  test "REST: login válido dentro do limite continua funcionando" do
    login(users(:one).email, "123456")

    assert_response :ok
    assert_equal users(:one).email, response.parsed_body.dig("user", "email")
  end

  test "GraphQL: userLogin é limitado por e-mail" do
    query = 'mutation { userLogin(email: "um@exemplo.com", password: "errada") { errors } }'
    5.times do
      post "/graphql", params: { query: query }, as: :json
      assert_nil response.parsed_body["errors"]
    end

    post "/graphql", params: { query: query }, as: :json
    assert_equal AuthThrottle::MESSAGE, response.parsed_body["errors"].first["message"]
  end

  test "GraphQL: userCreate é limitado por IP" do
    5.times do |i|
      post "/graphql", params: { query: %(mutation { userCreate(email: "novo#{i}@x.com", password: "senhaforte123") { errors } }) }, as: :json
      assert_nil response.parsed_body["errors"]
      assert_empty response.parsed_body.dig("data", "userCreate", "errors")
    end

    post "/graphql", params: { query: 'mutation { userCreate(email: "novo9@x.com", password: "senhaforte123") { errors } }' }, as: :json
    assert_equal AuthThrottle::MESSAGE, response.parsed_body["errors"].first["message"]
    assert_not User.exists?(email: "novo9@x.com")
  end
end
