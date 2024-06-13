---
layout: open_source
author: Juan Aparicio
title: Warped
category: Ruby, Rails
short_description: A gem to increase the productivity of your Rails development.
github_url: https://github.com/gogrow-dev/warped
---

This is a gem that I created to increase the productivity of my Rails development. The idea behind it is to provide a set of tools that I find myself using in every client MVP I work on.

Not every project is the same, but there are some patterns that I find myself repeating over and over again. For example:
- Index views with search, filters, sorting and pagination.
- Writing one line jobs that wrap a service call.
- Writing the same base service class for encapsulating logic

So, I decided to create a gem that provides all of these tools, and I can selectively include them in my projects. This way, I can focus on the business logic of the project, and not on writing the same boilerplate code over and over again.

The usage of the gem is pretty simple. Add the gem to the Gemfile, and then include the modules you want to use in your project. For example:

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  include Warped::Controllers::Pageable
  include Warped::Controllers::Filterable

  filterable_by :email, name: 'user_name'

  # GET /users
  # GET /users?page=1&per_page=10
  # GET /users?email.rel=in&email=user@example.com&email=other@example.com
  def index
    @users = paginate(filter(User.all))

    render json: {data: @users, meta: page_info }
  end
end

# app/services/user/seed.rb
class User::Seed < Warped::Services::Base
  enable_job!

  def call
    1000.times do |i|
      User.create(name: "User #{i}")
    end
  end
end

User::Seed.call # => This will create 1000 users in the database
User::Seed.call_later # => This will queue a User::Seed::Job in the application job adapter.
User::Seed::Job.perform_later # => This will queue a User::Seed::Job in the application job adapter.
```

These are just a few examples of what the gem provides. You can check the [documentation]({{ page.github_url }}/blob/main/README.md) for more information on how to use it.

From all of the projects I have worked on, this is the one that I am most proud of. It has helped me a lot in my day-to-day work, and I hope it can help you too.
