---
layout: open_source
author: Juan Aparicio
title: Prest
category: Ruby, Rails
short_description: An HTTParty wrapper for easier RESTful API consumption.
github_url: https://github.com/gogrow-dev/prest
---

This is really one of the first ruby projects I did with the sole purpose of trying some new things I learned while reading the book ["Metaprogramming Ruby 2"](https://pragprog.com/titles/ppmetr2/metaprogramming-ruby-2/).

The idea behind the gem, was making a wrapper for the [HTTParty gem](https://github.com/jnunemaker/httparty), that would allow me to consume RESTful APIs in a more declarative way; just like I access `ActiveRecord` models in Rails.

What does this look like then? Well, let's say you have a RESTful API that has a `GET /users` endpoint. With `Prest`, you could do something like this:

```ruby
# => GET https://api.example.com/users
Prest::Client.new('https://api.example.com').users.get!

# => GET https://api.example.com/users/1
Prest::Client.new('https://api.example.com').users(1).get!

# => GET https://api.example.com/users/1/posts
Prest::Client.new('https://api.example.com').users(1).posts.get!

# => POST https://api.example.com/users/1/posts
example_client = Prest::Client.new('https://api.example.com')
example_client.users(1).posts.post!(body: { title: 'New Gem!' })
```

Besides providing a client, `Prest` also provides a `Prest::Service` so that endpoints can be encapsulated into a Client/Service class, and then used in a more Rails-like way.

```ruby
class Github::API < Prest::Service
  def artifacts(owner, repo)
    repos(owner).repo(repo).artifacts
  end

  private

  def base_uri
    'https://api.github.com'
  end

  def options
    {
      headers: {
        'access_token' => ENV['GITHUB_ACCESS_TOKEN']
      }
    }
  end
end

# => GET https://api.github.com/users/juan-apa/pulls
Github::API.users('juan-apa').pulls.get

# => GET https://api.github.com/users/juan-apa/repos
Github::API.users('juan-apa').repos.get

# => GET https://api.github.com/repos/juan-apa/prest/actions/artifacts
Github::API.artifacts('juan-apa', 'prest').get
```
