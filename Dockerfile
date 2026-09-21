FROM ruby:3

COPY ./ /blog/
WORKDIR /blog/
RUN gem install jekyll && bundle install

EXPOSE 4000

CMD ["bundle", "exec",  "jekyll serve -H 0.0.0.0"]
