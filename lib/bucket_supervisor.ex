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

defmodule Odo.BucketSupervisor do
  @moduledoc false

  use Supervisor

  @name Odo.BucketSupervisor

  def start_link do
      Supervisor.start_link(__MODULE__, nil, name: @name)
  end

  def start_child(name, bucket_size, bucket_refill_amount, bucket_refill_duration, skew) do
      Supervisor.start_child(@name, [name, bucket_size, bucket_refill_amount, bucket_refill_duration, skew])
  end

  def init(_) do
      children = [
          worker(Odo.Bucket, [])
      ]

      supervise(children, strategy: :simple_one_for_one)
  end
end
