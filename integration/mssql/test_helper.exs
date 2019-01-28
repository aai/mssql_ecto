Logger.configure(level: :info)

ExUnit.start(
  exclude: [
    :array_type,
    :map_type,
    :uses_usec,
    :uses_msec,
    :modify_foreign_key_on_update,
    :create_index_if_not_exists,
    :not_supported_by_sql_server,
    :upsert,
    :upsert_all,
    :identity_insert
  ]
)

# Configure Ecto for support and tests
Application.put_env(:ecto, :primary_key_type, :id)
Application.put_env(:ecto, :lock_for_update, "FOR UPDATE")
# Load support files
Code.require_file("./support/repo.exs", __DIR__)
Code.require_file("./support/schemas.exs", __DIR__)
Code.require_file("./support/migration.exs", __DIR__)

pool =
  case System.get_env("ECTO_POOL") || "poolboy" do
    "poolboy" -> DBConnection.Poolboy
    "sbroker" -> DBConnection.Sojourn
  end

# Basic test repo
alias Ecto.Integration.TestRepo

Application.put_env(
  :ecto,
  TestRepo,
  adapter: MssqlEcto,
  username: System.get_env("MSSQL_UID"),
  password: System.get_env("MSSQL_PWD"),
  database: "mssql_ecto_integration_test",
  migration_lock: "FOR UPDATE",
  pool: Ecto.Adapters.SQL.Sandbox
)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo,
    otp_app: :ecto,
    adapter: MssqlEcto
end

# Pool repo for transaction and lock tests
alias Ecto.Integration.PoolRepo

Application.put_env(
  :ecto,
  PoolRepo,
  adapter: MssqlEcto,
  username: System.get_env("MSSQL_UID"),
  password: System.get_env("MSSQL_PWD"),
  database: "mssql_ecto_integration_test",
  max_restarts: 20,
  max_seconds: 10
)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo,
    otp_app: :ecto,
    adapter: MssqlEcto

  def create_prefix(prefix) do
    "create schema #{prefix}"
  end

  def drop_prefix(prefix) do
    "drop schema #{prefix}"
  end
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
  end
end

{:ok, _} = MssqlEcto.ensure_all_started(TestRepo, :temporary)

# Load up the repository, start it, and run migrations
config = TestRepo.config()
_ = MssqlEcto.storage_down(config)
:ok = MssqlEcto.storage_up(config)

{:ok, _pid} = TestRepo.start_link()
{:ok, _pid} = PoolRepo.start_link()

query = "SELECT DB_NAME() AS [Current Database]"
Ecto.Adapters.SQL.query!(TestRepo, query)
|> IO.inspect()

query = "SELECT * from INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'"
Ecto.Adapters.SQL.query!(TestRepo, query)
|> IO.inspect()

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)
