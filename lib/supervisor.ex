#   Copyright 2017 Nigel Smith
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

defmodule Odo.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link do
      Supervisor.start_link(__MODULE__, nil)
  end

  def init(_) do
      children = [
          supervisor(Registry, [:unique, :odo_bucket_registry]),
          supervisor(Odo.BucketSupervisor, [])
      ]

      supervise(children, strategy: :rest_for_one)
  end
end
