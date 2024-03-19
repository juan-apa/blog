---
layout: blog
author: Juan Aparicio
---
The N+1 problem is a common performance issue that's present in most rails apps I've worked in. It occurs when listing a collection of objects and, for each object, fetching associations from the database is required.

In this post, I'll focus on a specific variation: displaying the count of associated objects.


## The Problem
Consider having a `User` model and a `Post` model, where a `User` has many `Post`s. The goal is to display the number of posts each user has in a list of users.

{:.not-prose}
```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_many :posts
end

# app/models/post.rb
class Post < ApplicationRecord
  belongs_to :user
end

# app/controllers/users_controller.rb
class UsersController < ApplicationController
  def index
    @users = User.all
  end
end
```

{:.not-prose}
```erb
<!-- app/views/users/index.html.erb -->
<% @users.each do |user| %>
  <p><%= user.name %>, <%= user.posts.count %> posts</p>
<% end %>
```

## Solving with counter caches
Rails' `counter_cache` feature is a straightforward solution for storing a running count of posts for each user, eliminating the need to query the database for this information.

{:.not-prose}
```ruby
# app/models/post.rb
class Post < ApplicationRecord
  belongs_to :user, counter_cache: true
end
```

{:.not-prose}
```erb
<!-- app/views/users/index.html.erb -->
<% @users.each do |user| %>
  <p><%= user.name %>, <%= user.posts_count %> posts</p>
<% end %>
```
### How this works
1. Add a `posts_count` column to the `users` table.
2. Add the `counter_cache: true` option to the `belongs_to` association in the `Post` model.
3. Rails will automatically update the `posts_count` column in the `users` table when posts are created, updated, or destroyed.

This method is often the first solution considered for addressing this issue.

### The problem with counter caches
While counter caches are effective in many scenarios, they have limitations, such as:
- Difficulty filtering the count of associated objects.
- Challenges updating records in bulk without triggering callbacks. (remember, `counter_cache` uses a callback in the model to update the count)
- The potential need for manual count updates due to the above issues.

## Solving with `includes` and `size`
An alternative solution involves using `includes` to eager load associated objects and then counting them in memory with the `size` method.

{:.not-prose}
```ruby
class User < ApplicationRecord
  has_many :posts

  delegate :size, to: :posts, prefix: true
end

# app/controllers/users_controller.rb
class UsersController < ApplicationController
  def index
    @users = User.includes(:posts)
  end
end
```

{:.not-prose}
```erb
<!-- app/views/users/index.html.erb -->
<% @users.each do |user| %>
  <p><%= user.name %>, <%= user.posts_size %> posts</p>
<% end %>
```

### How this works
1. Eager load the posts for each user.
2. Use the `delegate` method to create a `posts_size` method that returns the count of posts for each user.
3. Use the `posts_size` method in the view to display the count.

This solution is great because it doesn't require any extra database columns, and it's more flexible than `counter_cache`. But it has a downside: it's not as performant as `counter_cache` because it needs to load all the associated objects into memory.

### The problem with `includes` and `size`
The potential downside of this approach, is when there are many associated records, which leads to a large amount of data being loaded into memory.

## Solving the filtered counter problem
For situations where `counter_cache` falls short, such as needing to filter counts of associated objects, the `counter_culture` gem offers a robust solution. However, embracing simplicity and minimizing dependencies is a valuable strategy. A Rails-centric approach can be just as effective

{:.prose-card}
[counter_culture](https://github.com/magnusvk/counter_culture) solves this problem really well. It provides a `counter_culture` method that takes a block to define the conditions for the counter. It also provides a `reset_counters` method to update the counters in bulk without triggering callbacks.

After re-reading the rails `ActiveRecord` documentation, I figured, that solving this is also dead-simple:

{:.not-prose}
```ruby
class User < ApplicationRecord
  has_many :posts
  has_many :published_posts, -> { where.not(published_at: nil) }, class_name: 'Post'

  delegate :size, to: :posts, prefix: true
  delegate :size, to: :published_posts, prefix: true
end

# app/controllers/users_controller.rb
class UsersController < ApplicationController
  def index
    @users = User.all.includes(:posts, :published_posts)
  end
end
```

{:.not-prose}
```erb
<!-- app/views/users/index.html.erb -->
<% @users.each do |user| %>
  <p><%= user.name %>, <%= user.posts_size %> posts, <%= user.published_posts_size %> published posts</p>
<% end %>
```

### How this works
1. Define a new association called `published_posts` that filters the posts that have a `published_at` date.
2. Use the `delegate` method to create a `published_posts_size` method that returns the count of published posts for each user.
3. Use the `published_posts_count` method in the view to display the count.

### Why is this not triggering N+1 queries?
Well, for a long time, I had a misconception about `size` method in `ActiveRecord::Relation`. I thought that calling `size` on an association would always load the associated objects into memory and count them there everytime.

However, this is not the case. When you call `size` on an association, it will check if the association has already been loaded into memory (in this case, by the `includes` method), and if it has, it will count the elements in memory. If it hasn't, it will execute a `SELECT COUNT(*) ...` query to the database.

So, in this case, the code is not triggering N+1 queries because the associated objects are eager-loaded into memory with `includes(:posts, :published_posts)`.

## Conclusion
The N+1 counters problem is a common issue when working with associations in rails. There are different solutions to the problem, and the best one depends on the specific requirements of your application.

- `counter_cache` is the go-to solution for the problem, but it has some limitations. Also, if you need to filter the count of associated objects or update records in bulk without triggering callbacks, it may not be the best solution.

- `counter_culture` gem is a great solution for the filtered counter problem, but it adds a dependency to your project, and also it will still be affected by the callback limitations.

- `includes` + `size` is a great solution for the problem, but it's not as performant as `counter_cache` (for reads!) because it needs to load all the associated objects into memory. If your collection is small, this is not a problem.

Maybe try to keep things simple in the beginning, use the tools that Rails provides, like counter_cache or includes + size. You can always refactor later if the need arises. Don't overcomplicate things from the start.
