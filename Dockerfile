FROM ruby:2
MAINTAINER Dan Boitnott <boitnott@sigcorp.com>

COPY Gemfile Gemfile.lock ellucian_git_mirror.rb /mirror/
COPY docker/run.sh /

RUN mkdir -p /mirror-data \
 && chmod 755 /run.sh \
 && cd /mirror \
 && bundle update --bundler \
 && bundle install

CMD /run.sh
