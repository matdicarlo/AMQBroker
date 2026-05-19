package it.producer.ProducerService;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class ScheduledComponent {

    private static final Logger log = LoggerFactory.getLogger(ScheduledComponent.class);

    @Autowired
    private ProducerService producerService;

    @Scheduled(fixedRate = 3000)
    public void buildBody() throws Exception {
        log.info("test scheduler");
        producerService.buildBody();
    }


}
